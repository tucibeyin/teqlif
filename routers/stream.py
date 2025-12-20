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
async def client_log(request: Request): return {"status": "ok"}

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
    async def kick_user(self, room, user): pass 

manager = ConnectionManager()

def cleanup_stream(username):
    log_server(f"{username} temizleniyor...")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

# --- 🔥 GARANTİLİ AKIŞ MOTORU 🔥 ---
def video_generator(filepath, ip):
    log_server(f"👀 İZLEYİCİ ({ip}) bağlandı.")
    
    # Dosyanın oluşmasını bekle (Max 10sn)
    for _ in range(20):
        if os.path.exists(filepath) and os.path.getsize(filepath) > 4096:
            break
        time.sleep(0.5)
    else:
        log_server(f"❌ Dosya bulunamadı veya boş: {filepath}")
        return

    with open(filepath, "rb") as f:
        # 1. HEADER (İlk 4KB - Dosya Kimliği)
        header = f.read(4096)
        if header: yield header
        
        # 2. KONUM BELİRLEME
        f.seek(0, 2) # Sona git
        total_size = f.tell()
        
        # Eğer dosya 2MB'dan büyükse, son 1MB'a atla (Canlı Yayın Modu)
        # Değilse, baştan başla (Header'dan hemen sonrası)
        seek_pos = 4096
        if total_size > (2 * 1024 * 1024):
            seek_pos = total_size - (1024 * 1024) # Son 1MB
            log_server(f"⏩ {ip} -> Canlıya atlandı (Son 1MB)")
        
        f.seek(seek_pos)

        # 3. KESİNTİSİZ AKIŞ DÖNGÜSÜ
        no_data_count = 0
        while True:
            chunk = f.read(64 * 1024) # 64KB Oku
            if chunk:
                yield chunk
                no_data_count = 0 # Veri gelirse sayacı sıfırla
            else:
                # Veri yoksa bekle (Yayın devam ediyor olabilir)
                time.sleep(0.1)
                no_data_count += 1
                
                # 10 saniye boyunca hiç veri gelmezse kapat (Yayın bitmiş olabilir)
                if no_data_count > 100:
                    log_server(f"👋 {ip} -> Veri akışı bitti.")
                    break

@router.get("/stream/{username}")
async def stream_video(username: str, request: Request):
    file_path = f"static/hls/{username}/stream.webm"
    return StreamingResponse(video_generator(file_path, request.client.host), media_type="video/webm")

# --- DİĞER ROTALAR ---
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
async def thumb(): return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

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
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
            if not data: break
            
            file_handle.write(data)
            file_handle.flush()
            os.fsync(file_handle.fileno())
            
    except Exception as e:
        log_server(f"❌ HATA: {e}")
    finally:
        file_handle.close()
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")