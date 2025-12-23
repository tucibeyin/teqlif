import os
import json
import shutil
import subprocess
import asyncio 
import sys
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user, SECRET_KEY, ALGORITHM

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- BAĞLANTI YÖNETİCİSİ ---
class ConnectionManager:
    def __init__(self): 
        self.rooms = {}

    async def connect(self, ws, room):
        await ws.accept()
        if room not in self.rooms: self.rooms[room] = []
        self.rooms[room].append(ws)
        await self.broadcast_viewer_count(room)

    def disconnect(self, ws, room):
        if room in self.rooms and ws in self.rooms[room]: 
            self.rooms[room].remove(ws)
            asyncio.create_task(self.broadcast_viewer_count(room)) 

    async def broadcast_to_room(self, msg, room):
        if room in self.rooms:
            for ws in self.rooms[room][:]:
                try: await ws.send_text(msg)
                except: self.rooms[room].remove(ws)

    async def broadcast_viewer_count(self, room):
        if room in self.rooms:
            count = len(self.rooms[room])
            viewer_count = max(0, count - 1) 
            message = json.dumps({"type": "viewer_update", "count": viewer_count})
            for ws in self.rooms[room][:]:
                try: await ws.send_text(message)
                except: pass

manager = ConnectionManager()

# 🔥 STATE MANAGEMENT (DURUM YÖNETİMİ) 🔥
# active_processes: { 'username': subprocess }
active_processes = {}
# pending_disconnects: { 'username': asyncio.Task } -> Silinmeyi bekleyen görevler
pending_disconnects = {}
active_auctions = {} 

# --- YARDIMCI FONKSİYONLAR ---

def kill_ffmpeg_process(username):
    """FFmpeg sürecini kesin olarak öldürür."""
    if username in active_processes:
        try:
            print(f"🛑 STREAM KİLL EDİLİYOR: {username}")
            active_processes[username].kill()
            active_processes[username].wait(timeout=0.1)
        except: pass
        del active_processes[username]
    
    # DB'de canlı durumunu kapat
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: 
            u.is_live = False
            db.commit()
    finally: 
        db.close()
    
    # İzleyicilere bitti bilgisini gönder
    asyncio.create_task(manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), username))

async def graceful_disconnect_timer(username, delay=30):
    """Bağlantı koptuğunda X saniye bekler, gelmezse öldürür."""
    print(f"⏳ BAĞLANTI KOPTU (GRACE PERIOD): {username} için {delay}sn bekleniyor...")
    try:
        await asyncio.sleep(delay)
        # Süre doldu, hala pending listesindeyse öldür
        if username in pending_disconnects:
            kill_ffmpeg_process(username)
            del pending_disconnects[username]
    except asyncio.CancelledError:
        print(f"⚡ YENİDEN BAĞLANDI: {username} (Sayaç iptal edildi)")

def write_to_ffmpeg(process, data):
    if process and process.stdin:
        try: process.stdin.write(data); process.stdin.flush()
        except: pass

# --- ENDPOINTS ---

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
    
    return templates.TemplateResponse("live.html", {
        "request": request, "user": user, "mode": mode, 
        "streams": active_streams, "broadcaster": target_user,
        "active_auctions": active_auctions
    })

@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.stream_title = title; user.stream_category = category; db.commit()
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    # Kullanıcı bilerek durdurduysa hemen öldür
    if user.username in pending_disconnects:
        pending_disconnects[user.username].cancel()
        del pending_disconnects[user.username]
    kill_ffmpeg_process(user.username)
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

@router.post("/gift/send")
async def send_gift(request: Request, user: User = Depends(get_current_user)):
    try:
        data = await request.json()
        target_user = data.get("to_user")
        await manager.broadcast_to_room(json.dumps({"type": "gift_received", "sender": user.username, "gift": "diamond"}), target_user)
        return {"status": "success"}
    except: return {"status": "error"}

@router.post("/broadcast/toggle_auction")
async def toggle_auction(request: Request, user: User = Depends(get_current_user)):
    data = await request.json()
    if data.get("action") == "start":
        if user.username not in active_auctions: active_auctions[user.username] = {"price": 0, "last_bidder": "-"}
        await manager.broadcast_to_room(json.dumps({"type": "auction_started", "price": active_auctions[user.username]["price"], "bidder": active_auctions[user.username]["last_bidder"]}), user.username)
    else:
        if user.username in active_auctions: del active_auctions[user.username]
        await manager.broadcast_to_room(json.dumps({"type": "auction_ended"}), user.username)
    return {"status": "ok"}

@router.post("/broadcast/reset_auction")
async def reset_auction(request: Request, user: User = Depends(get_current_user)):
    active_auctions[user.username] = {"price": 0, "last_bidder": "-"}
    await manager.broadcast_to_room(json.dumps({"type": "auction_update", "price": 0, "bidder": "-"}), user.username)
    return {"status": "ok"}

@router.post("/broadcast/bid")
async def bid(request: Request, user: User = Depends(get_current_user)):
    data = await request.json()
    target = data.get("broadcaster"); amount = int(data.get("amount", 10))
    if target in active_auctions:
        active_auctions[target]["price"] += amount; active_auctions[target]["last_bidder"] = user.username
        await manager.broadcast_to_room(json.dumps({"type": "auction_update", "price": active_auctions[target]["price"], "bidder": user.username}), target)
    return {"status": "ok"}

@router.websocket("/ws/chat")
async def chat(websocket: WebSocket, stream: str = "home"):
    await manager.connect(websocket, stream)
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            if msg.get("type") == "chat_message":
                await manager.broadcast_to_room(json.dumps({"type": "chat_message", "user": msg.get("user"), "text": msg.get("text")}), stream)
    except: manager.disconnect(websocket, stream)

@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    user = None
    try:
        from jose import jwt
        user = db.query(User).filter(User.email == jwt.decode(websocket.cookies.get("access_token").partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM]).get("sub")).first()
    except: await websocket.close(); return

    # 🔥 RECONNECT LOGIC (YENİDEN BAĞLANMA MANTIĞI) 🔥
    # Eğer kullanıcı daha önce düşmüşse ve süresi dolmadan geri geldiyse:
    if user.username in pending_disconnects:
        # Silinme görevini iptal et
        pending_disconnects[user.username].cancel()
        del pending_disconnects[user.username]
        print(f"✅ SESSION KURTARILDI: {user.username}")
    
    # Eğer süreç zaten yoksa (yeni yayın), başlat
    if user.username not in active_processes:
        user.is_live = True; db.commit()
        stream_dir = f"static/hls/{user.username}"; shutil.rmtree(stream_dir, ignore_errors=True); os.makedirs(stream_dir, exist_ok=True)
        
        # ABR FFMPEG KOMUTU
        cmd = [
            "ffmpeg", "-f", "webm", "-i", "pipe:0",
            "-filter_complex", 
            "[0:v]split=4[v1][v2][v3][v4];[v1]scale=-2:240[v240];[v2]scale=-2:360[v360];[v3]scale=-2:480[v480];[v4]scale=-2:720[v720]",
            "-map", "[v240]", "-map", "a:0", "-c:v:0", "libx264", "-b:v:0", "300k", "-maxrate:v:0", "350k", "-bufsize:v:0", "500k", "-c:a:0", "aac", "-b:a:0", "64k", "-ar", "44100",
            "-map", "[v360]", "-map", "a:0", "-c:v:1", "libx264", "-b:v:1", "600k", "-maxrate:v:1", "650k", "-bufsize:v:1", "1000k", "-c:a:1", "aac", "-b:a:1", "96k", "-ar", "44100",
            "-map", "[v480]", "-map", "a:0", "-c:v:2", "libx264", "-b:v:2", "1200k", "-maxrate:v:2", "1300k", "-bufsize:v:2", "2000k", "-c:a:2", "aac", "-b:a:2", "128k", "-ar", "44100",
            "-map", "[v720]", "-map", "a:0", "-c:v:3", "libx264", "-b:v:3", "2500k", "-maxrate:v:3", "2700k", "-bufsize:v:3", "4000k", "-c:a:3", "aac", "-b:a:3", "128k", "-ar", "44100",
            "-preset", "ultrafast", "-tune", "zerolatency", "-g", "48", "-keyint_min", "48", "-sc_threshold", "0", "-af", "aresample=async=1",
            "-f", "hls", "-hls_time", "2", "-hls_list_size", "4", "-hls_flags", "delete_segments+omit_endlist",
            "-master_pl_name", "index.m3u8", "-var_stream_map", "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3",
            f"{stream_dir}/stream_%v.m3u8"
        ]
        active_processes[user.username] = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=sys.stderr, start_new_session=True)

    proc = active_processes.get(user.username)
    loop = asyncio.get_event_loop()

    try:
        while True:
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=60.0)
            if not data: break
            # Eğer süreç dışarıdan öldürüldüyse (zaman aşımı vs) döngüyü kır
            if user.username not in active_processes: break
            await loop.run_in_executor(None, write_to_ffmpeg, proc, data)
    except: 
        pass # Disconnect hatası normal
    finally:
        # 🔥 HEMEN ÖLDÜRME, ZAMANLAYICI BAŞLAT (30 Sn) 🔥
        if user.username in active_processes:
            task = asyncio.create_task(graceful_disconnect_timer(user.username, delay=30))
            pending_disconnects[user.username] = task