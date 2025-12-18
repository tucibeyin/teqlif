import os
import json
import shutil
import subprocess
import sys
import asyncio 
import time
from datetime import datetime
# 🔥 Request ve diğerleri eklendi
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User, StreamRestriction
from utils import get_current_user

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- MÜŞTERİ LOGLARI İÇİN ENDPOINT ---
@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        msg = data.get("msg", "")
        level = data.get("level", "INFO")
        # Sunucu konsoluna bas (Renkli ve belirgin)
        print(f"📱 [CLIENT-{level}] {msg}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- SOCKET YÖNETİCİSİ ---
class ConnectionManager:
    def __init__(self): self.rooms = {}
    async def connect(self, ws, room, user):
        await ws.accept()
        if room not in self.rooms: self.rooms[room] = []
        self.rooms[room].append({"ws": ws, "user": user})
    async def disconnect(self, ws, room):
        if room in self.rooms:
            self.rooms[room] = [c for c in self.rooms[room] if c["ws"] != ws]
    async def broadcast_to_room(self, msg, room):
        if room in self.rooms:
            for c in self.rooms[room]:
                try: await c["ws"].send_text(msg)
                except: pass
    async def kick_user(self, room, user): pass 

manager = ConnectionManager()
active_processes = {}

def cleanup_stream(username):
    print(f"🛑 SERVER: {username} yayını temizleniyor...")
    if username in active_processes:
        try:
            active_processes[username].terminate()
            active_processes[username].wait(timeout=2)
        except: 
            active_processes[username].kill()
        if username in active_processes: del active_processes[username]
    
    # DB Temizliği
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; u.is_auction_active = False; db.commit()
    except: pass
    finally: db.close()

def write_to_ffmpeg(process, data):
    if process and process.stdin: 
        try:
            process.stdin.write(data)
            process.stdin.flush()
        except: pass

# --- STANDART API ---
@router.post("/stream/restrict")
async def restrict(target_username: str = Form(...), action: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return {"status": "ok"} 

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    
    target_user = None
    if broadcaster:
        target_user = db.query(User).filter(User.username == broadcaster).first()
    
    active_streams = db.query(User).filter(User.is_live == True).all()
    if mode == "broadcast": target_user = user

    return templates.TemplateResponse("live.html", {
        "request": request, "user": user, "mode": mode, "streams": active_streams, "broadcaster": target_user, "auction_active": False
    })

@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.is_live = True; user.stream_title = title; user.stream_category = category; db.commit()
    print(f"✅ SERVER: {user.username} yayını başlattı.")
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
        with open(f"static/thumbnails/thumb_{user.username}.jpg", "wb") as f:
            f.write(base64.b64decode(d['image'].split(",")[1]))
        return {"status": "ok"}
    except: return {"status": "error"}

@router.post("/broadcast/toggle_auction")
async def toggle_auction(active: bool = Form(...)): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(user: User=Depends(get_current_user)): return {"status": "success", "new_balance": user.diamonds}

@router.websocket("/ws/chat")
async def chat(ws: WebSocket, stream: str = "home"):
    await manager.connect(ws, stream, "Guest")
    try:
        while True:
            d = await ws.receive_text()
            await manager.broadcast_to_room(json.dumps({"type": "chat", "user": "Guest", "msg": d}), stream)
    except: await manager.disconnect(ws, stream)

@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    user = None
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        from utils import SECRET_KEY, ALGORITHM
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: pass
    
    if not user: await websocket.close(); return

    stream_dir = f"static/hls/{user.username}"
    if not os.path.exists(stream_dir):
        os.makedirs(f"{stream_dir}/720p", exist_ok=True); os.makedirs(f"{stream_dir}/480p", exist_ok=True)
        os.makedirs(f"{stream_dir}/360p", exist_ok=True); os.makedirs(f"{stream_dir}/240p", exist_ok=True)

    print(f"🎥 SERVER: FFmpeg başlatılıyor: {user.username}")

    # STABİL AYARLAR (WebM Giriş -> H.264 Çıkış)
    command = [
        "ffmpeg", 
        "-f", "webm", 
        "-analyzeduration", "1000000", "-probesize", "1000000", 
        "-fflags", "+genpts+igndts+nobuffer+discardcorrupt", 
        "-i", "pipe:0",
        
        "-filter_complex", 
        "[0:v]scale=-2:720,crop=406:720:(in_w-406)/2:0,split=4[v720][v480][v360][v240];"
        "[v720]copy[out720]; [v480]scale=270:-2[out480]; [v360]scale=202:-2[out360]; [v240]scale=136:-2[out240]",
        
        "-preset", "veryfast", "-tune", "zerolatency", "-threads", "0", 
        "-af", "aresample=async=1",
        
        "-profile:v", "baseline", "-level", "3.0", 
        "-g", "60", "-keyint_min", "60", "-sc_threshold", "0", 
        "-force_key_frames", "expr:gte(t,n_forced*2)", 
        "-pix_fmt", "yuv420p",

        "-map", "[out720]", "-map", "0:a", "-c:v:0", "libx264", "-b:v:0", "1500k", "-maxrate:v:0", "1800k", "-bufsize:v:0", "3000k", "-c:a:0", "aac", "-b:a:0", "128k",
        "-map", "[out480]", "-map", "0:a", "-c:v:1", "libx264", "-b:v:1", "800k", "-maxrate:v:1", "1000k", "-bufsize:v:1", "1500k", "-c:a:1", "aac", "-b:a:1", "96k",
        "-map", "[out360]", "-map", "0:a", "-c:v:2", "libx264", "-b:v:2", "500k", "-maxrate:v:2", "800k", "-bufsize:v:2", "1000k", "-c:a:2", "aac", "-b:a:2", "64k",
        "-map", "[out240]", "-map", "0:a", "-c:v:3", "libx264", "-b:v:3", "300k", "-maxrate:v:3", "400k", "-bufsize:v:3", "500k", "-c:a:3", "aac", "-b:a:3", "48k",
        
        "-f", "hls", "-hls_time", "2", "-hls_list_size", "6", 
        "-hls_flags", "delete_segments+omit_endlist+discont_start+program_date_time", 
        "-hls_allow_cache", "0",
        "-var_stream_map", "v:0,a:0,name:720p v:1,a:1,name:480p v:2,a:2,name:360p v:3,a:3,name:240p",
        "-master_pl_name", "master.m3u8", f"{stream_dir}/%v/stream.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr) # Logları sistem loguna bas
    active_processes[user.username] = process
    
    async def wait_for_stream():
        start_t = time.time()
        while time.time() - start_t < 30:
            if os.path.exists(f"{stream_dir}/master.m3u8"):
                print(f"✅ SERVER: Master m3u8 oluştu! {user.username}")
                new_db = SessionLocal()
                u = new_db.query(User).filter(User.username == user.username).first()
                u.is_live = True; new_db.commit(); new_db.close()
                payload = json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""})
                await manager.broadcast_to_room(payload, "home")
                break
            await asyncio.sleep(0.5)

    loop = asyncio.get_event_loop()
    loop.create_task(wait_for_stream())

    try:
        while True:
            # 5 Saniye Veri Gelmezse Kapat
            try:
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=5.0)
                if not data: break
                await loop.run_in_executor(None, write_to_ffmpeg, process, data)
            except asyncio.TimeoutError:
                print(f"⚠️ SERVER: Timeout - Veri gelmedi {user.username}")
                break 
    except Exception as e:
        print(f"❌ SERVER HATASI: {e}")
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")