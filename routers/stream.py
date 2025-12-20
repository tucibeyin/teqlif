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

    print(f"🎥 ULTRA PREMIUM YAYIN (4 KALİTE): {user.username}")

    # 🔥 FFmpeg 4-WAY ADAPTIVE STREAMING 🔥
    # Tek giriş -> 4 Çıkış (720p, 480p, 360p, 240p)
    # CPU'yu kullanır ama kaliteyi garanti eder.
    command = [
        "ffmpeg", 
        "-f", "webm", 
        "-i", "pipe:0",
        
        # Karmaşık Filtre: Videoyu 4'e böl ve her birini yeniden boyutlandır
        "-filter_complex", 
        "[0:v]split=4[v1][v2][v3][v4];"
        "[v1]scale=-2:720[v720];"
        "[v2]scale=-2:480[v480];"
        "[v3]scale=-2:360[v360];"
        "[v4]scale=-2:240[v240]",
        
        # --- 1. Stream: 720p (High) ---
        "-map", "[v720]", "-c:v:0", "libx264", "-b:v:0", "2500k", "-maxrate:v:0", "2800k", "-bufsize:v:0", "5000k",
        "-preset", "veryfast", "-g", "48", "-sc_threshold", "0", "-keyint_min", "48",
        
        # --- 2. Stream: 480p (Medium) ---
        "-map", "[v480]", "-c:v:1", "libx264", "-b:v:1", "1200k", "-maxrate:v:1", "1400k", "-bufsize:v:1", "2400k",
        "-preset", "veryfast", "-g", "48", "-sc_threshold", "0", "-keyint_min", "48",
        
        # --- 3. Stream: 360p (Low) ---
        "-map", "[v360]", "-c:v:2", "libx264", "-b:v:2", "700k", "-maxrate:v:2", "800k", "-bufsize:v:2", "1400k",
        "-preset", "veryfast", "-g", "48", "-sc_threshold", "0", "-keyint_min", "48",

        # --- 4. Stream: 240p (Mobile Saver) ---
        "-map", "[v240]", "-c:v:3", "libx264", "-b:v:3", "300k", "-maxrate:v:3", "400k", "-bufsize:v:3", "600k",
        "-preset", "veryfast", "-g", "48", "-sc_threshold", "0", "-keyint_min", "48",
        
        # --- SES (Her birine kopyala) ---
        "-map", "a:0", "-map", "a:0", "-map", "a:0", "-map", "a:0",
        "-c:a", "aac", "-b:a", "128k", "-ac", "2",
        
        # --- HLS MASTER ---
        "-f", "hls", 
        "-hls_time", "2", 
        "-hls_list_size", "5",
        "-hls_flags", "delete_segments+omit_endlist+split_by_time",
        "-master_pl_name", "master.m3u8",
        "-var_stream_map", "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3",
        f"{stream_dir}/stream_%v.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    active_processes[user.username] = process
    
    # DB Bildirim (Multi-bitrate başlaması 8-10 saniye sürebilir)
    async def notify():
        await asyncio.sleep(8) 
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