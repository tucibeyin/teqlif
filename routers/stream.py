import os
import json
import shutil
import subprocess
import sys
import base64
from typing import Dict, List, Optional
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form, BackgroundTasks
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import desc
from sqlalchemy.orm import Session
from database import get_db
from models import User, StreamMessage
from utils import get_current_user, send_broadcast_notifications_task, SECRET_KEY, ALGORITHM
from jose import jwt

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# Connection Manager
class ConnectionManager:
    def __init__(self):
        self.rooms: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, room_name: str):
        await websocket.accept()
        if room_name not in self.rooms: self.rooms[room_name] = []
        self.rooms[room_name].append(websocket)
        await self.broadcast_count(room_name)

    async def disconnect(self, websocket: WebSocket, room_name: str):
        if room_name in self.rooms:
            if websocket in self.rooms[room_name]: self.rooms[room_name].remove(websocket)
            await self.broadcast_count(room_name)
            if not self.rooms[room_name]: del self.rooms[room_name]

    async def broadcast_count(self, room_name: str):
        if room_name in self.rooms:
            count = len(self.rooms[room_name])
            msg = json.dumps({"type": "count", "val": count})
            for conn in self.rooms[room_name][:]:
                try: await conn.send_text(msg)
                except: pass

    async def broadcast_to_room(self, message: str, room_name: str):
        if room_name in self.rooms:
            for conn in self.rooms[room_name][:]:
                try: await conn.send_text(message)
                except: pass

manager = ConnectionManager()
active_processes: Dict[str, subprocess.Popen] = {}

def cleanup_stream(username: str, db: Session):
    print(f"🧹 TEMİZLİK: {username}")
    try:
        user = db.query(User).filter(User.username == username).first()
        if user:
            user.is_live = False; user.is_auction_active = False
            user.current_price = 0; user.highest_bidder = None
            db.commit()
    except: pass

    if username in active_processes:
        proc = active_processes[username]
        try: proc.terminate(); proc.wait(timeout=2)
        except: proc.kill()
        del active_processes[username]
    
    shutil.rmtree(f"static/hls/{username}", ignore_errors=True)

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: Optional[str] = None, user: Optional[User] = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    target_user = None
    is_following = False
    if broadcaster:
        target_user = db.query(User).filter(User.username == broadcaster).first()
        if target_user and target_user in user.followed: is_following = True

    if mode == "broadcast":
        return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": "broadcast", "streams": [], "auction_active": user.is_auction_active})
    else:
        active_streams = db.query(User).filter(User.is_live == True).all()
        return templates.TemplateResponse("live.html", {
            "request": request, "user": user, "mode": "watch", "streams": active_streams,
            "auction_active": target_user.is_auction_active if target_user else False,
            "is_following": is_following, "broadcaster": target_user
        })

@router.post("/broadcast/start")
async def start_broadcast_api(background_tasks: BackgroundTasks, title: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_live = True; user.stream_title = title; db.commit()
    emails = [f.email for f in user.followers]
    background_tasks.add_task(send_broadcast_notifications_task, emails, user.username)
    return {"status": "success"}

@router.post("/broadcast/stop")
async def stop_broadcast_api(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    cleanup_stream(user.username, db)
    return {"status": "stopped"}

@router.post("/broadcast/toggle_auction")
async def toggle_auction(active: bool = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_auction_active = active; db.commit()
    msg = json.dumps({"type": "auction_state", "active": active})
    await manager.broadcast_to_room(msg, user.username)
    await manager.broadcast_to_room(msg, "broadcast")
    return {"status": "ok", "active": active}

@router.post("/broadcast/thumbnail")
async def upload_thumbnail(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    try:
        data = await request.json()
        image_data = data['image'].split(",")[1]
        filename = f"thumb_{user.username}.jpg"
        with open(f"static/thumbnails/{filename}", "wb") as f: f.write(base64.b64decode(image_data))
        user.thumbnail = f"/static/thumbnails/{filename}?t={data['timestamp']}"
        db.commit()
        return {"status": "ok"}
    except: return {"status": "error"}

@router.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket, stream: str = "general", db: Session = Depends(get_db)):
    room_name = stream
    await manager.connect(websocket, room_name)
    current_username = "Misafir"
    try:
        token = websocket.cookies.get("access_token")
        if token:
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            u = db.query(User).filter(User.email == payload.get("sub")).first()
            if u: current_username = u.username
    except: pass

    broadcaster = db.query(User).filter(User.username == stream).first()
    if broadcaster:
        init_msg = json.dumps({"type": "init", "price": broadcaster.current_price, "leader": broadcaster.highest_bidder})
        await websocket.send_text(init_msg)

    try:
        while True:
            data = await websocket.receive_text()
            if data.strip():
                is_bid = data.startswith("BID:")
                safe_msg = data.replace("<", "&lt;")
                new_msg = StreamMessage(room_name=stream, sender=current_username, message=safe_msg, is_bid=is_bid)
                db.add(new_msg)
                
                if is_bid and broadcaster:
                    try:
                        amount = int(data.split(":")[1])
                        if amount > broadcaster.current_price:
                            broadcaster.current_price = amount; broadcaster.highest_bidder = current_username; db.add(broadcaster)
                    except: pass
                db.commit()
                msg_payload = json.dumps({"type": "chat", "user": current_username, "msg": safe_msg})
                await manager.broadcast_to_room(msg_payload, room_name)
    except: await manager.disconnect(websocket, room_name)

@router.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    user = None
    try:
        token = websocket.cookies.get("access_token")
        if token:
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: pass

    if not user or not user.username: await websocket.close(); return

    # Klasör yapısını ayarla: static/hls/user/v0, static/hls/user/v1 vb.
    stream_dir = f"static/hls/{user.username}"
    shutil.rmtree(stream_dir, ignore_errors=True)
    
    # Alt klasörleri oluştur (FFmpeg otomatik oluşturmazsa diye)
    os.makedirs(f"{stream_dir}/720p", exist_ok=True)
    os.makedirs(f"{stream_dir}/480p", exist_ok=True)
    os.makedirs(f"{stream_dir}/360p", exist_ok=True)
    
    print(f"🎥 ADAPTİF YAYIN BAŞLIYOR: {user.username}")

    # 🔥 ABR (ADAPTIVE BITRATE) FFMPEG KOMUTU
    command = [
        "ffmpeg", 
        "-f", "webm", 
        "-fflags", "+genpts+igndts+nobuffer", 
        "-i", "pipe:0",

        # --- GÖRÜNTÜ İŞLEME VE BOYUTLANDIRMA ---
        "-filter_complex", 
        "[0:v]split=3[v1][v2][v3];"            # Gelen videoyu 3 kopyaya ayır
        "[v1]scale=-2:720[v720];"             # Kopya 1 -> 720p
        "[v2]scale=-2:480[v480];"             # Kopya 2 -> 480p
        "[v3]scale=-2:360[v360]",             # Kopya 3 -> 360p

        # --- 720p AYARLARI (Yüksek Kalite) ---
        "-map", "[v720]", "-map", "0:a",
        "-c:v:0", "libx264", "-b:v:0", "2500k", "-maxrate:v:0", "2800k", "-bufsize:v:0", "2800k",
        "-c:a:0", "aac", "-b:a:0", "128k",

        # --- 480p AYARLARI (Orta Kalite) ---
        "-map", "[v480]", "-map", "0:a",
        "-c:v:1", "libx264", "-b:v:1", "1200k", "-maxrate:v:1", "1400k", "-bufsize:v:1", "1400k",
        "-c:a:1", "aac", "-b:a:1", "96k",

        # --- 360p AYARLARI (Düşük Kalite / Mobil) ---
        "-map", "[v360]", "-map", "0:a",
        "-c:v:2", "libx264", "-b:v:2", "600k", "-maxrate:v:2", "700k", "-bufsize:v:2", "700k",
        "-c:a:2", "aac", "-b:a:2", "64k",

        # --- ORTAK AYARLAR (Hız ve Gecikme) ---
        "-preset", "veryfast",                # İşlemciyi daha az yorar
        "-tune", "zerolatency",               # Düşük gecikme için
        "-g", "60",                           # 2 saniyede bir keyframe (HLS time 2sn ile uyumlu)
        "-sc_threshold", "0",
        
        # --- HLS YAPILANDIRMASI ---
        "-f", "hls",
        "-hls_time", "2",                     # Parça uzunluğu 2 saniye
        "-hls_list_size", "4",                # Listede son 4 parça tutulur
        "-hls_flags", "delete_segments+append_list+omit_endlist+discont_start",
        
        # --- MASTER PLAYLIST OLUŞTURMA ---
        "-var_stream_map", "v:0,a:0,name:720p v:1,a:1,name:480p v:2,a:2,name:360p",
        "-master_pl_name", "master.m3u8",     # Ana dosya ismi
        
        # --- ÇIKTI DOSYA YOLLARI ---
        "-hls_segment_filename", f"{stream_dir}/%v/seg_%03d.ts",  # Parçalar: 720p/seg_001.ts
        f"{stream_dir}/%v/stream.m3u8",                           # Alt listeler: 720p/stream.m3u8
        
        "-loglevel", "error"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr)
    active_processes[user.username] = process

    try:
        while True:
            data = await websocket.receive_bytes()
            if process.stdin:
                try: process.stdin.write(data); process.stdin.flush()
                except: break
    except: pass
    finally:
        cleanup_stream(user.username, db)