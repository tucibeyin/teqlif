import os
import json
import shutil
import asyncio 
import time
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse, StreamingResponse
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
        print(f"📱 [CLIENT] {data.get('msg')}")
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
    print(f"🛑 SERVER: {username} temizleniyor...")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; u.is_auction_active = False; db.commit()
    except: pass
    finally: db.close()

# --- VİDEO OKUYUCU ---
def video_generator(filepath):
    # Dosya oluşana kadar bekle
    tries = 0
    while not os.path.exists(filepath):
        time.sleep(0.5)
        tries += 1
        if tries > 20: return 

    with open(filepath, "rb") as f:
        while True:
            data = f.read(1024 * 64)
            if not data:
                time.sleep(0.1)
                continue
            yield data

@router.get("/stream/{username}")
async def stream_video(username: str):
    file_path = f"static/hls/{username}/stream.webm"
    return StreamingResponse(video_generator(file_path), media_type="video/webm")

# --- STANDART ROTALAR ---
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
        import base64
        with open(f"static/thumbnails/thumb_{user.username}.jpg", "wb") as f:
            f.write(base64.b64decode(d['image'].split(",")[1]))
        return {"status": "ok"}
    except: return {"status": "ok"}

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
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: pass
    
    if not user: await websocket.close(); return

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    print(f"🎥 YAYIN BAŞLIYOR (DEBUG MODE): {user.username}")
    
    video_path = f"{stream_dir}/stream.webm"
    file_handle = open(video_path, "wb")

    async def notify_live():
        await asyncio.sleep(2)
        print(f"✅ YAYIN AKTİF: {user.username}")
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        payload = json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""})
        await manager.broadcast_to_room(payload, "home")

    loop = asyncio.get_event_loop()
    loop.create_task(notify_live())

    total_bytes = 0
    packet_count = 0

    try:
        while True:
            try:
                # Veri bekleme günlüğü
                # print(f"⏳ Veri bekleniyor... ({user.username})") 
                
                # 20 saniye timeout
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
                
                if not data: 
                    print(f"⚠️ Boş veri alındı! ({user.username})")
                    break
                
                # Veri yazma
                file_handle.write(data)
                file_handle.flush()
                
                # İstatistik
                total_bytes += len(data)
                packet_count += 1
                
                # Her 5 pakette bir log bas (Sistemi yormadan takibi sağlar)
                if packet_count % 5 == 0:
                    print(f"📥 ALINDI: {len(data)} byte | Toplam: {total_bytes/1024:.1f} KB | Dosya Yazıldı: Evet")

            except asyncio.TimeoutError:
                print(f"⚠️ SERVER: Timeout (Veri Akışı Kesildi) - {user.username}")
                break 
    except Exception as e:
        print(f"❌ SERVER HATASI: {e}")
    finally:
        file_handle.close()
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")