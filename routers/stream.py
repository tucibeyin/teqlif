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

# --- MANAGER ---
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
    if username in active_processes:
        proc = active_processes[username]
        try: proc.terminate(); proc.wait()
        except: pass
        del active_processes[username]
    
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

# --- YAYINCI ---
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

    print(f"🎥 MULTI-BITRATE HLS BAŞLIYOR: {user.username}")

    # 🔥 FFmpeg MULTI-BITRATE (720p & 360p) 🔥
    # Tek giriş -> İki çıkış (High/Low)
    # CPU tasarrufu için 'ultrafast' ve 'zerolatency' kullanıyoruz.
    command = [
        "ffmpeg", 
        "-f", "webm", 
        "-i", "pipe:0",
        
        # Filtre: Videoyu 2'ye böl, biri 720p (v1), biri 360p (v2) olsun
        "-filter_complex", "[0:v]split=2[v1][v2]; [v1]scale=-2:720[v720]; [v2]scale=-2:360[v360]",
        
        # Stream 1: 720p (High Quality)
        "-map", "[v720]", "-c:v:0", "libx264", "-b:v:0", "2000k", "-preset", "ultrafast", "-tune", "zerolatency", "-g", "48",
        
        # Stream 2: 360p (Low Quality / Mobile Saver)
        "-map", "[v360]", "-c:v:1", "libx264", "-b:v:1", "600k", "-preset", "ultrafast", "-tune", "zerolatency", "-g", "48",
        
        # Audio (Her ikisi için ortak)
        "-map", "a:0", "-map", "a:0", "-c:a", "aac", "-b:a", "64k", "-ac", "2",
        
        # HLS Ayarları
        "-f", "hls", 
        "-hls_time", "2", 
        "-hls_list_size", "4",
        "-hls_flags", "delete_segments+omit_endlist+split_by_time",
        
        # Master Playlist Oluştur (Otomatik Geçiş İçin)
        "-master_pl_name", "master.m3u8",
        "-var_stream_map", "v:0,a:0 v:1,a:1",
        f"{stream_dir}/stream_%v.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    active_processes[user.username] = process
    
    # DB Bildirim
    async def notify():
        await asyncio.sleep(6) # HLS oluşması için biraz daha zaman ver
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        await manager.broadcast_to_room(json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""}), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    try:
        while True:
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
            if not data: break
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
    except: pass
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")