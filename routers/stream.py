import os
import json
import shutil
import subprocess
import sys
import asyncio 
import time
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User, StreamRestriction
from utils import get_current_user

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- Loglama ---
@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"📱 [CLIENT] {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- Socket Manager ---
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
active_logs = {}

def log_to_file(username, message):
    try:
        with open(f"static/hls/{username}/stream.log", "a") as f:
            f.write(f"[{time.strftime('%H:%M:%S')}] {message}\n")
    except: pass

def cleanup_stream(username):
    print(f"🛑 SERVER: {username} temizleniyor...")
    if username in active_processes:
        proc = active_processes[username]
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except: proc.kill()
        del active_processes[username]
    
    if username in active_logs:
        try: active_logs[username].close()
        except: pass
        del active_logs[username]

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

# --- Routes ---
@router.post("/stream/restrict")
async def restrict(target_username: str = Form(...), action: str = Form(...), user: User = Depends(get_current_user)): return {"status": "ok"} 

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    target_user = None
    if broadcaster: target_user = db.query(User).filter(User.username == broadcaster).first()
    active_streams = db.query(User).filter(User.is_live == True).all()
    if mode == "broadcast": target_user = user
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": active_streams, "broadcaster": target_user, "auction_active": False})

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
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(f"{stream_dir}/480p", exist_ok=True)
    os.makedirs(f"{stream_dir}/240p", exist_ok=True) # Sadece 2 kalite

    log_file = open(f"{stream_dir}/stream.log", "w")
    active_logs[user.username] = log_file
    print(f"🎥 YAYIN BAŞLIYOR (PERFORMANCE MODE): {user.username}")

    # 🔥 CPU DOSTU FFmpeg AYARLARI 🔥
    # -preset ultrafast: CPU kullanımını minimize eder (Speed > 1.0x garanti olsun diye)
    # Sadece 2 stream (480p ve 240p)
    command = [
        "ffmpeg", 
        "-f", "matroska", 
        "-analyzeduration", "500000", "-probesize", "500000", # Hızlı analiz
        "-fflags", "+genpts+igndts+nobuffer+discardcorrupt",
        "-err_detect", "ignore_err",
        "-i", "pipe:0",
        
        "-filter_complex", 
        "[0:v]scale=-2:480,split=2[v480][v240];" # Girişi direk 480p yap ve böl
        "[v480]copy[out480];" # 480p'yi kopyala (zaten scale edildi)
        "[v240]scale=-2:240[out240]", # 240p üret
        
        "-preset", "ultrafast", # 🔥 EN ÖNEMLİ AYAR: Hız > Sıkıştırma
        "-tune", "zerolatency", 
        
        "-profile:v", "baseline", "-level", "3.0", 
        "-g", "60", "-keyint_min", "60", "-sc_threshold", "0", 
        "-pix_fmt", "yuv420p",

        # 480p (Ana Kalite)
        "-map", "[out480]", "-map", "0:a", 
        "-c:v:0", "libx264", "-b:v:0", "1000k", "-maxrate:v:0", "1200k", "-bufsize:v:0", "1500k", 
        "-c:a:0", "aac", "-b:a:0", "128k",

        # 240p (Düşük Kalite)
        "-map", "[out240]", "-map", "0:a", 
        "-c:v:1", "libx264", "-b:v:1", "400k", "-maxrate:v:1", "500k", "-bufsize:v:1", "600k", 
        "-c:a:1", "aac", "-b:a:1", "64k",
        
        "-f", "hls", "-hls_time", "2", "-hls_list_size", "6", 
        "-hls_flags", "delete_segments+omit_endlist+discont_start+program_date_time", 
        "-var_stream_map", "v:0,a:0,name:480p v:1,a:1,name:240p",
        "-master_pl_name", "master.m3u8", f"{stream_dir}/%v/stream.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=log_file)
    active_processes[user.username] = process
    
    async def wait_for_stream():
        start_t = time.time()
        while time.time() - start_t < 30:
            if os.path.exists(f"{stream_dir}/master.m3u8"):
                log_to_file(user.username, "✅ YAYIN AKTİF")
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
            try:
                # 10 saniye veri gelmezse kapat
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=10.0)
                if not data: break
                await loop.run_in_executor(None, write_to_ffmpeg, process, data)
            except asyncio.TimeoutError:
                log_to_file(user.username, "⚠️ TIMEOUT")
                break 
    except Exception as e:
        log_to_file(user.username, f"❌ HATA: {e}")
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")