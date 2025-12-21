import os
import json
import shutil
import subprocess
import asyncio 
import sys
from datetime import datetime
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
    async def connect(self, ws, room):
        await ws.accept()
        if room not in self.rooms: self.rooms[room] = []
        self.rooms[room].append(ws)
    def disconnect(self, ws, room):
        if room in self.rooms and ws in self.rooms[room]: self.rooms[room].remove(ws)
    async def broadcast_to_room(self, msg, room):
        if room in self.rooms:
            for ws in self.rooms[room][:]:
                try: await ws.send_text(msg)
                except: self.rooms[room].remove(ws)

manager = ConnectionManager()
active_processes = {}

def cleanup_stream_sync(username):
    print(f"🛑 SERVER: {username} temizleniyor...")
    if username in active_processes:
        proc = active_processes[username]
        try: proc.kill(); proc.wait(timeout=0.1)
        except: pass
        del active_processes[username]
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

async def cleanup_stream_async(username):
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, cleanup_stream_sync, username)

def write_to_ffmpeg(process, data):
    if process and process.stdin:
        try: process.stdin.write(data); process.stdin.flush()
        except: pass

@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    target_user = None
    active_streams = db.query(User).filter(User.is_live == True).all()
    if broadcaster:
        target_user = db.query(User).filter(User.username == broadcaster).first()
        if target_user in active_streams:
            active_streams.remove(target_user)
            active_streams.insert(0, target_user)
    if mode == "broadcast": target_user = user
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": active_streams, "broadcaster": target_user})

@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.stream_title = title; user.stream_category = category; db.commit()
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    asyncio.create_task(cleanup_stream_async(user.username))
    await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")
    return {"status": "stopped"}

@router.post("/broadcast/thumbnail")
async def thumb(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        d = await request.json()
        import base64
        with open(f"static/thumbnails/thumb_{user.username}.jpg", "wb") as f: f.write(base64.b64decode(d['image'].split(",")[1]))
        user.thumbnail = f"/static/thumbnails/thumb_{user.username}.jpg"; db.commit()
    except: pass
    return {"status": "ok"}

# 🔥 HEDİYE 🔥
@router.post("/gift/send")
async def send_gift(request: Request, user: User = Depends(get_current_user)):
    try:
        data = await request.json()
        target_user = data.get("to_user")
        gift_type = data.get("gift_type", "diamond")
        await manager.broadcast_to_room(json.dumps({"type": "gift_received", "sender": user.username, "gift": gift_type}), target_user)
        return {"status": "success"}
    except: return {"status": "error"}

# 🔥 SOHBET 🔥
@router.websocket("/ws/chat")
async def chat(websocket: WebSocket, stream: str = "home"):
    await manager.connect(websocket, stream)
    try:
        while True:
            data = await websocket.receive_text()
            msg_obj = json.loads(data)
            if msg_obj.get("type") == "chat_message":
                await manager.broadcast_to_room(json.dumps({"type": "chat_message", "user": msg_obj.get("user"), "text": msg_obj.get("text")}), stream)
    except: manager.disconnect(websocket, stream)

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

    user.is_live = True; db.commit()
    print(f"🎥 YAYIN BAŞLIYOR (TURBO 1s): {user.username}")

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    # 🔥 FFmpeg TURBO MOD (1 Saniye Gecikme Hedefi) 🔥
    # -hls_time 1: 1 saniyelik parçalar
    # -g 24: 1 saniyede bir keyframe (Mecburi)
    # -hls_list_size 5: Liste kısa tutulur
    command = [
        "ffmpeg", "-f", "webm", "-i", "pipe:0",
        "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-profile:v", "baseline",
        "-level", "3.0", "-pix_fmt", "yuv420p", 
        "-r", "24", "-g", "24", "-keyint_min", "24", "-sc_threshold", "0", 
        "-vsync", "1",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "3000k", "-vf", "scale=-2:540",
        "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-af", "aresample=async=1",
        "-f", "hls", "-hls_time", "1", "-hls_list_size", "5", 
        "-hls_flags", "delete_segments+omit_endlist",
        f"{stream_dir}/index.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr, start_new_session=True)
    active_processes[user.username] = process
    
    async def notify():
        await asyncio.sleep(2) # Daha hızlı bildirim
        await manager.broadcast_to_room(json.dumps({
            "type": "stream_added", "username": user.username, 
            "title": user.stream_title, "category": user.stream_category, 
            "thumbnail": f"/static/thumbnails/thumb_{user.username}.jpg"
        }), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    try:
        while True:
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=60.0)
            if not data: break
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
    except: pass
    finally:
        asyncio.create_task(cleanup_stream_async(user.username))
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")