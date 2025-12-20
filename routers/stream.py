import os
import json
import shutil
import asyncio 
import time
from datetime import datetime
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user, SECRET_KEY, ALGORITHM

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- RENKLİ LOGLAMA ---
def log_server(msg):
    t = datetime.now().strftime("%H:%M:%S")
    print(f"[{t}] 🖥️ SERVER: {msg}")

@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        t = datetime.now().strftime("%H:%M:%S")
        # Client loglarını log dosyasına bas
        print(f"[{t}] 📱 CLIENT: {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- SOCKET MANAGER ---
class ConnectionManager:
    def __init__(self): self.rooms = {}
    async def connect(self, ws, room, user):
        await ws.accept()
    async def disconnect(self, ws, room): pass
    async def broadcast_to_room(self, msg, room): pass 

manager = ConnectionManager()

def cleanup_stream(username):
    log_server(f"{username} temizleniyor...")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

# --- VİDEO OKUYUCU ---
def video_generator(filepath, viewer_ip):
    log_server(f"İzleyici ({viewer_ip}) dosya istiyor: {filepath}")
    tries = 0
    while not os.path.exists(filepath):
        time.sleep(0.5)
        tries += 1
        if tries > 20: 
            log_server(f"❌ Dosya bulunamadı! ({filepath})")
            return 

    with open(filepath, "rb") as f:
        while True:
            data = f.read(1024 * 64)
            if not data:
                time.sleep(0.1)
                continue
            yield data

@router.get("/stream/{username}")
async def stream_video(username: str, request: Request):
    return StreamingResponse(video_generator(f"static/hls/{username}/stream.webm", request.client.host), media_type="video/webm")

# --- ROUTERLAR ---
@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 
@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    streams = db.query(User).filter(User.is_live == True).all()
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": streams, "broadcaster": None})

@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.is_live = True; user.stream_title = title; user.stream_category = category; db.commit()
    log_server(f"Yayın kaydı DB'de açıldı: {user.username}")
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    cleanup_stream(user.username)
    return {"status": "stopped"}

@router.post("/broadcast/thumbnail")
async def thumb(): return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

# --- 🔥 GÖBEK (YAYINCI) SOCKETİ 🔥 ---
@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    log_server("Socket bağlantısı kabul edildi.")
    
    # Kimlik
    user = None
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
        username = user.username
        log_server(f"Kullanıcı: {username}")
    except: 
        log_server("❌ Kimlik doğrulama hatası!")
        await websocket.close()
        return

    # Klasör
    stream_dir = f"static/hls/{username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)
    
    video_path = f"{stream_dir}/stream.webm"
    file_handle = open(video_path, "wb")
    log_server(f"Dosya açıldı: {video_path}")

    packet_count = 0
    total_bytes = 0

    try:
        while True:
            try:
                # Veri Bekleme
                # log_server(f"⏳ Veri bekleniyor...") 
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
                
                if not data: 
                    log_server("⚠️ Boş veri geldi (Connection Closed?)")
                    break
                
                size = len(data)
                packet_count += 1
                total_bytes += size
                
                # Yazma
                file_handle.write(data)
                file_handle.flush()
                os.fsync(file_handle.fileno()) # Zorla diske yaz
                
                # DETAYLI LOG
                # Her 5 pakette bir diskteki boyutunu kontrol edip basıyoruz
                if packet_count % 5 == 0:
                    disk_size = os.path.getsize(video_path)
                    log_server(f"📥 ALINDI: {size} B | TOPLAM: {total_bytes/1024:.1f} KB | 💾 DİSK: {disk_size/1024:.1f} KB")

            except asyncio.TimeoutError:
                log_server(f"💀 TIMEOUT! {username} veri göndermeyi kesti.")
                break 
    except Exception as e:
        log_server(f"❌ HATA: {e}")
    finally:
        file_handle.close()
        cleanup_stream(username)