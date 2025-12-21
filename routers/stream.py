import os
import json
import shutil
import subprocess
import asyncio 
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user, SECRET_KEY, ALGORITHM

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.post("/log/client")
async def client_log(request: Request): return {"status": "ok"}

class ConnectionManager:
    def __init__(self): self.rooms = {}
    async def connect(self, ws, room, user):
        await ws.accept()
        if room not in self.rooms: self.rooms[room] = []
        self.rooms[room].append({"ws": ws, "user": user})
    async def disconnect(self, ws, room): pass 
    async def broadcast_to_room(self, msg, room):
        if room in self.rooms:
            for c in self.rooms[room]:
                try: await c["ws"].send_text(msg)
                except: pass

manager = ConnectionManager()
active_processes = {}

def cleanup_stream(username):
    print(f"🛑 SERVER: {username} temizleniyor...")
    # FFmpeg'i öldür
    if username in active_processes:
        proc = active_processes[username]
        try: proc.terminate(); proc.wait()
        except: pass
        del active_processes[username]
    
    # Klasörü hemen silme (izleyiciler son kısımları izleyebilsin), ama DB'den düşür
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

def write_to_ffmpeg(process, data):
    if process and process.stdin:
        try: process.stdin.write(data); process.stdin.flush()
        except: pass

# --- ROUTES ---
@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 
@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    target_user = None
    if broadcaster: target_user = db.query(User).filter(User.username == broadcaster).first()
    active_streams = db.query(User).filter(User.is_live == True).all()
    if mode == "broadcast": target_user = user
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": active_streams, "broadcaster": target_user})
@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.is_live = True; user.stream_title = title; user.stream_category = category; db.commit()
    return {"status": "ok"}
@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    cleanup_stream(user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")
    return {"status": "stopped"}
@router.post("/broadcast/thumbnail")
async def thumb(request: Request, user: User = Depends(get_current_user)):
    try:
        d = await request.json()
        import base64
        with open(f"static/thumbnails/thumb_{user.username}.jpg", "wb") as f:
            f.write(base64.b64decode(d['image'].split(",")[1]))
    except: pass
    return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

# --- YAYINCI SOCKETİ ---
@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    
    user = None
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: await websocket.close(); return

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    print(f"🎥 TURBO YAYIN (Low Latency): {user.username}")

    # 🔥 FFmpeg TURBO AYARLARI 🔥
    command = [
        "ffmpeg", 
        "-f", "webm",       # Girdi formatı
        "-i", "pipe:0",     # Girdi kaynağı (WebSocket)
        
        # --- PERFORMANS AYARLARI ---
        "-fflags", "nobuffer",          # Girdi tamponunu kapat
        "-flags", "low_delay",          # Düşük gecikme bayrağı
        "-strict", "experimental",
        
        # --- VİDEO ÇIKIŞI (H.264) ---
        "-c:v", "libx264", 
        "-preset", "ultrafast",         # En yüksek kodlama hızı
        "-tune", "zerolatency",         # Canlı yayın için sıfır gecikme modu
        "-r", "24",                     # FPS Sabitle (Donmayı önler)
        "-b:v", "1500k",                # 1.5 Mbps (Kaliteli ve hızlı)
        "-vf", "scale=-2:540",          # 540p (qHD) - Mobil için ideal, işlemci dostu
        "-g", "48",                     # Keyframe aralığı (2 saniye)
        "-sc_threshold", "0",           # Sahne değişiminde keyframe atma
        
        # --- SES ÇIKIŞI (AAC) ---
        "-c:a", "aac", 
        "-b:a", "128k", 
        "-ac", "2", 
        "-ar", "44100",
        
        # --- HLS AYARLARI (HIZLI PARÇALAR) ---
        "-f", "hls", 
        "-hls_time", "1",               # 1 Saniyelik parçalar (Çok hızlı güncellenir)
        "-hls_list_size", "5",          # Listede 5 parça tut
        "-hls_flags", "delete_segments+omit_endlist+split_by_time",
        "-hls_segment_type", "mpegts",  # iOS için en uyumlu format
        f"{stream_dir}/index.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    active_processes[user.username] = process
    
    # DB Bildirim (Hemen 2. saniyede başlat)
    async def notify():
        await asyncio.sleep(2) # 1 saniyelik parça oluşması için 2sn yeter
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        await manager.broadcast_to_room(json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""}), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    try:
        while True:
            # Veri bekleme süresi
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=15.0)
            if not data: break
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
    except: pass
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")