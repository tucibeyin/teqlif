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
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"📱 [CLIENT] {datetime.now().strftime('%H:%M:%S')} | {data.get('msg', '')}")
        return {"status": "ok"}
    except: return {"status": "err"}

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
    user.stream_title = title
    user.stream_category = category
    db.commit()
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
        file_path = f"static/thumbnails/thumb_{user.username}.jpg"
        with open(file_path, "wb") as f:
            f.write(base64.b64decode(d['image'].split(",")[1]))
        user.thumbnail = f"/{file_path}"
        db.commit()
    except Exception: pass
    return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

# --- SOCKET ---
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

    user.is_live = True
    db.commit()
    print(f"🎥 YAYIN BAŞLIYOR: {user.username}")

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    # 🔥 FFmpeg (LEVEL 3.1 FIX) 🔥
    # -level 3.1: 720p HD yayını destekler (Level 3.0 yetmiyordu)
    # -hls_flags independent_segments: Her parça tek başına oynatılabilir (Takılmayı önler)
    command = [
        "ffmpeg", 
        "-f", "webm", "-i", "pipe:0",
        
        "-c:v", "libx264", 
        "-preset", "veryfast", 
        "-profile:v", "baseline",
        "-level", "3.1",          # <-- KRİTİK DEĞİŞİKLİK
        "-pix_fmt", "yuv420p",
        "-r", "24", 
        "-g", "48",               # 2 Saniye Keyframe (Stabilite için)
        "-keyint_min", "48",
        "-sc_threshold", "0",
        "-b:v", "2000k", 
        "-vf", "scale=-2:540",
        
        "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-af", "aresample=async=1",
        
        "-f", "hls", 
        "-hls_time", "2",         # 2 Saniyelik parçalar (Daha güvenli)
        "-hls_list_size", "6", 
        "-hls_flags", "delete_segments+omit_endlist+split_by_time+independent_segments",
        f"{stream_dir}/index.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr, start_new_session=True)
    active_processes[user.username] = process
    
    async def notify():
        await asyncio.sleep(3) 
        await manager.broadcast_to_room(json.dumps({
            "type": "stream_added", 
            "username": user.username, 
            "title": user.stream_title or "Canlı", 
            "category": user.stream_category or "Genel", 
            "thumbnail": f"/static/thumbnails/thumb_{user.username}.jpg"
        }), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    packet_count = 0
    try:
        while True:
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=60.0)
            if not data: break
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
            
            packet_count += 1
            if packet_count % 50 == 0:
                print(f"📥 VERİ: {packet_count} pkt")
                
    except Exception as e:
        print(f"❌ SOCKET HATA: {e}")
    finally:
        asyncio.create_task(cleanup_stream_async(user.username))
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")