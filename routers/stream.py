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
    print(f"🎥 YAYIN BAŞLIYOR (MULTI-QUALITY): {user.username}")

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    # 🔥 FFmpeg 4 KALİTE (Adaptive Bitrate) 🔥
    # Gelen yayını alır, 4 parçaya böler ve her birini ayrı işler.
    # Level 3.1 ve Baseline profilini KORUDUK (Stil bozulmasın diye).
    command = [
        "ffmpeg", 
        "-f", "webm", "-i", "pipe:0",
        
        # Filtre: Videoyu 4 kopyaya ayır ve boyutlandır
        "-filter_complex", 
        "[0:v]split=4[v720][v480][v360][v240];"
        "[v720]scale=-2:720[vo720];"
        "[v480]scale=-2:480[vo480];"
        "[v360]scale=-2:360[vo360];"
        "[v240]scale=-2:240[vo240]",
        
        # --- 1. Stream: 720p (High) ---
        "-map", "[vo720]", "-c:v:0", "libx264", "-b:v:0", "2500k", "-maxrate:v:0", "2800k", "-bufsize:v:0", "5000k",
        "-preset", "ultrafast", "-profile:v:0", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p", "-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
        
        # --- 2. Stream: 480p (Medium) ---
        "-map", "[vo480]", "-c:v:1", "libx264", "-b:v:1", "1200k", "-maxrate:v:1", "1400k", "-bufsize:v:1", "2500k",
        "-preset", "ultrafast", "-profile:v:1", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p", "-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
        
        # --- 3. Stream: 360p (Low) ---
        "-map", "[vo360]", "-c:v:2", "libx264", "-b:v:2", "800k", "-maxrate:v:2", "900k", "-bufsize:v:2", "1800k",
        "-preset", "ultrafast", "-profile:v:2", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p", "-g", "48", "-keyint_min", "48", "-sc_threshold", "0",

        # --- 4. Stream: 240p (Very Low) ---
        "-map", "[vo240]", "-c:v:3", "libx264", "-b:v:3", "400k", "-maxrate:v:3", "450k", "-bufsize:v:3", "900k",
        "-preset", "ultrafast", "-profile:v:3", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p", "-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
        
        # --- SES (Her kaliteye kopyala) ---
        "-map", "a:0", "-map", "a:0", "-map", "a:0", "-map", "a:0",
        "-c:a", "aac", "-b:a", "64k", "-ac", "2", "-af", "aresample=async=1",
        
        # --- HLS MASTER PLAYLIST ---
        "-f", "hls", 
        "-hls_time", "2", 
        "-hls_list_size", "6", 
        "-hls_flags", "delete_segments+omit_endlist+split_by_time+independent_segments",
        "-master_pl_name", "master.m3u8", # Ana dosya
        "-var_stream_map", "v:0,a:0,name:720p v:1,a:1,name:480p v:2,a:2,name:360p v:3,a:3,name:240p",
        f"{stream_dir}/stream_%v.m3u8" # Alt dosyalar
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr, start_new_session=True)
    active_processes[user.username] = process
    
    async def notify():
        await asyncio.sleep(4) # 4 yayın oluşması biraz sürebilir
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