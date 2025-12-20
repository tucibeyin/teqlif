import asyncio
import json
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- GLOBAL RELAY HAFIZASI ---
# Canlı yayın verilerini burada tutacağız (Disk yerine RAM)
# Format: { "username": { "header": bytearray, "viewers": set() } }
active_relays = {}

# --- Loglama ---
@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"📱 [CLIENT] {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- Socket Manager (Chat İçin) ---
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

manager = ConnectionManager()

# --- STANDART API ---
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
    # Relay odasını hazırla
    if user.username not in active_relays:
        active_relays[user.username] = {"header": None, "viewers": set()}
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    # Temizlik
    if user.username in active_relays:
        del active_relays[user.username]
        
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == user.username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()
    
    await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")
    return {"status": "stopped"}

@router.post("/broadcast/thumbnail")
async def thumb(request: Request, user: User = Depends(get_current_user)):
    # Thumbnail opsiyonel, hata verirse sistemi durdurmasın
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

# --- WEBSOCKETS ---

@router.websocket("/ws/chat")
async def chat(ws: WebSocket, stream: str = "home"):
    await manager.connect(ws, stream, "Guest")
    try:
        while True:
            d = await ws.receive_text()
            await manager.broadcast_to_room(json.dumps({"type": "chat", "user": "Guest", "msg": d}), stream)
    except: await manager.disconnect(ws, stream)

# 🔥 YAYINCI SOCKETİ (FFMPEG YOK, SADECE AKTARIM) 🔥
@router.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    
    # Basit Kimlik Doğrulama
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        from utils import SECRET_KEY, ALGORITHM
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: 
        await websocket.close()
        return

    username = user.username
    print(f"🎥 RELAY BAŞLADI: {username}")
    
    # Hafıza alanını oluştur
    if username not in active_relays:
        active_relays[username] = {"header": None, "viewers": set()}

    # Yayını Aktif İşaretle
    user.is_live = True; db.commit()
    await manager.broadcast_to_room(json.dumps({"type": "stream_added", "username": username, "title": "Canlı", "category": "Genel", "thumbnail": ""}), "home")

    try:
        while True:
            # Veriyi al
            data = await websocket.receive_bytes()
            
            # İlk paket genellikle başlık (header) bilgisidir, bunu sakla
            # İzleyiciler sonradan gelirse bu başlığa ihtiyaç duyarlar
            if active_relays[username]["header"] is None:
                active_relays[username]["header"] = data
                print(f"✅ HEADER ALINDI ({len(data)} bytes)")
            
            # Bağlı olan tüm izleyicilere gönder
            viewers = list(active_relays[username]["viewers"])
            for viewer_ws in viewers:
                try:
                    await viewer_ws.send_bytes(data)
                except:
                    # İzleyici kopmuşsa listeden sil
                    active_relays[username]["viewers"].discard(viewer_ws)
                    
    except WebSocketDisconnect:
        print(f"🛑 RELAY DURDU: {username}")
    finally:
        if username in active_relays:
            del active_relays[username]
        # DB Kapat
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()

# 🔥 İZLEYİCİ SOCKETİ (YENİ) 🔥
@router.websocket("/ws/watch/{username}")
async def watch_endpoint(websocket: WebSocket, username: str):
    await websocket.accept()
    
    if username not in active_relays:
        await websocket.close()
        return

    # İzleyiciyi listeye ekle
    active_relays[username]["viewers"].add(websocket)
    print(f"👀 YENİ İZLEYİCİ: {username}")

    try:
        # Eğer yayıncının header'ı varsa, önce onu gönder (Başlatmak için şart)
        if active_relays[username]["header"]:
            await websocket.send_bytes(active_relays[username]["header"])
        
        # Sonsuz döngüde bekle (Veri yayıncıdan gelecek)
        while True:
            await websocket.receive_text() # Kalp atışı için beklenebilir
    except:
        if username in active_relays:
            active_relays[username]["viewers"].discard(websocket)