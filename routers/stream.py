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

def log(tag, msg):
    """Renkli ve zaman damgalı log fonksiyonu"""
    t = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    print(f"[{t}] {tag}: {msg}")

@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        log("📱 CLIENT", data.get('msg'))
        return {"status": "ok"}
    except: return {"status": "err"}

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

def cleanup_stream(username):
    log("🛑 SERVER", f"{username} yayını temizleniyor...")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; u.is_auction_active = False; db.commit()
    except: pass
    finally: db.close()

# --- VİDEO OKUYUCU (İZLEYİCİ İÇİN) ---
def video_generator(filepath, viewer_ip):
    log("👀 SERVER", f"İzleyici ({viewer_ip}) dosya bekliyor: {filepath}")
    
    # Dosya oluşana kadar bekle
    tries = 0
    while not os.path.exists(filepath):
        time.sleep(0.5)
        tries += 1
        if tries > 20: 
            log("❌ SERVER", f"Dosya bulunamadı, izleyici düştü: {filepath}")
            return 

    log("✅ SERVER", f"Dosya bulundu, akış başlıyor: {filepath}")
    
    with open(filepath, "rb") as f:
        while True:
            data = f.read(1024 * 64) # 64KB Oku
            if not data:
                time.sleep(0.1)
                continue
            yield data

@router.get("/stream/{username}")
async def stream_video(username: str, request: Request):
    client_ip = request.client.host
    file_path = f"static/hls/{username}/stream.webm"
    return StreamingResponse(video_generator(file_path, client_ip), media_type="video/webm")

# --- YAYINCI SOCKETİ ---
@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    log("🔌 SERVER", "WebSocket bağlantısı kabul edildi.")
    
    user = None
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
        log("👤 SERVER", f"Kullanıcı doğrulandı: {user.username}")
    except Exception as e:
        log("❌ SERVER", f"Auth Hatası: {e}")
        await websocket.close()
        return

    # Dosya Yolu Hazırla
    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)
    
    video_path = f"{stream_dir}/stream.webm"
    log("📂 SERVER", f"Dosya oluşturuluyor: {video_path}")
    
    try:
        file_handle = open(video_path, "wb")
    except Exception as e:
        log("❌ SERVER", f"Dosya Açma Hatası: {e}")
        await websocket.close()
        return

    # Bildirim
    async def notify_live():
        await asyncio.sleep(1)
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        payload = json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""})
        await manager.broadcast_to_room(payload, "home")
        log("📢 SERVER", "Yayın başladı bildirimi gönderildi.")

    loop = asyncio.get_event_loop()
    loop.create_task(notify_live())

    packet_count = 0
    total_bytes = 0

    try:
        log("🚀 SERVER", "Veri döngüsü başladı, paket bekleniyor...")
        while True:
            try:
                # 20 sn timeout
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
                
                if not data: 
                    log("⚠️ SERVER", "Boş veri paketi alındı, döngü kırılıyor.")
                    break
                
                packet_size = len(data)
                packet_count += 1
                total_bytes += packet_size
                
                # Diske Yaz
                file_handle.write(data)
                file_handle.flush()
                os.fsync(file_handle.fileno()) 
                
                # Detaylı Log (Her 10 pakette bir veya büyük paketlerde)
                if packet_count % 10 == 0:
                    current_size = os.path.getsize(video_path)
                    log("📥 SERVER", f"Paket #{packet_count} | Boyut: {packet_size} B | Toplam Alınan: {total_bytes/1024:.1f} KB | Dosya Boyutu: {current_size/1024:.1f} KB")

            except asyncio.TimeoutError:
                log("💀 SERVER", f"TIMEOUT! {user.username} kullanıcısından 20 saniyedir veri gelmiyor.")
                break 
            except Exception as e:
                log("❌ SERVER", f"Yazma Döngüsü Hatası: {e}")
                break
    finally:
        file_handle.close()
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")

# --- DİĞERLERİ ---
@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 
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
    log("✅ SERVER", f"Yayın kaydı DB'de açıldı: {user.username}")
    return {"status": "ok"}
@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    cleanup_stream(user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")
    return {"status": "stopped"}
@router.post("/broadcast/thumbnail")
async def thumb(request: Request): return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
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