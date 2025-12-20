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

def log_server(msg):
    t = datetime.now().strftime("%H:%M:%S")
    print(f"[{t}] 🖥️ SERVER: {msg}")

@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"[{datetime.now().strftime('%H:%M:%S')}] 📱 CLIENT: {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

class ConnectionManager:
    def __init__(self): self.rooms = {}
    async def connect(self, ws, room, user):
        await ws.accept()
    async def disconnect(self, ws, room): pass 
    async def broadcast_to_room(self, msg, room):
        if room in self.rooms:
            for c in self.rooms[room]:
                try: await c["ws"].send_text(msg)
                except: pass
    async def kick_user(self, room, user): pass 

manager = ConnectionManager()

def cleanup_stream(username):
    log_server(f"{username} temizleniyor...")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

# --- 🔥 SENKRONİZE AKIŞ MOTORU 🔥 ---
def video_generator(filepath, ip):
    log_server(f"👀 İZLEYİCİ ({ip}) bağlandı. Senkronizasyon yapılıyor...")
    
    # Dosyayı bekle
    tries = 0
    while not os.path.exists(filepath):
        time.sleep(0.5)
        tries += 1
        if tries > 20: return 

    with open(filepath, "rb") as f:
        # 1. HEADER GÖNDER (İlk 4KB)
        # WebM dosyasının kimliği buradadır, bunu almazsa oynatmaz.
        header = f.read(4096)
        yield header
        
        # 2. CANLI UCA ATLA (JUMP TO LIVE)
        # Dosyanın sonuna git
        f.seek(0, 2)
        file_size = f.tell()
        
        # Eğer dosya büyükse (yayın ilerlemişse), son 150KB'a geri sar.
        # Bu yaklaşık 1-2 saniyelik bir tampon sağlar, böylece keyframe yakalarız.
        buffer_size = 150 * 1024 
        
        if file_size > (4096 + buffer_size):
            f.seek(file_size - buffer_size)
            log_server(f"⏩ {ip} için canlı uca atlandı (Son 150KB).")
        else:
            # Yayın yeni başlamışsa kaldığı yerden devam et
            f.seek(4096)

        # 3. AKIŞ DÖNGÜSÜ
        while True:
            data = f.read(1024 * 64)
            if not data:
                time.sleep(0.05) # Veri yoksa bekle (Ultra düşük gecikme için süre kısaltıldı)
                continue
            yield data

@router.get("/stream/{username}")
async def stream_video(username: str, request: Request):
    file_path = f"static/hls/{username}/stream.webm"
    return StreamingResponse(video_generator(file_path, request.client.host), media_type="video/webm")

# --- STANDART ENDPOINTS (Aynı) ---
@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 
@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    target_user = None
    if broadcaster: target_user = db.query(User).filter(User.username == broadcaster).first()
    active_streams = db.query(User).filter(User.is_live == True).all()
    if mode == "broadcast": target_user = user
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": active_streams, "broadcaster": target_user}) # auction_active removed temp
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
async def thumb(): return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

# --- YAYINCI SOCKET ---
@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    
    user = None
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: 
        await websocket.close()
        return

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)
    
    video_path = f"{stream_dir}/stream.webm"
    file_handle = open(video_path, "wb")
    
    # DB Güncelleme
    async def notify():
        await asyncio.sleep(1)
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        await manager.broadcast_to_room(json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""}), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    try:
        while True:
            # Veri bekleme süresini optimize ettik
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
            if not data: break
            
            file_handle.write(data)
            file_handle.flush()
            os.fsync(file_handle.fileno()) # Hızlı yazma için önemli
            
    except Exception as e:
        log_server(f"❌ HATA: {e}")
    finally:
        file_handle.close()
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")