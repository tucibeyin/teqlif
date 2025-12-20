import os
import json
import shutil
import asyncio 
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

# --- Basit Socket Manager ---
class ConnectionManager:
    def __init__(self): self.rooms = {}
    async def connect(self, ws, room, user):
        await ws.accept()
    async def disconnect(self, ws, room): pass
    async def broadcast_to_room(self, msg, room): pass

manager = ConnectionManager()

def cleanup_stream(username):
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()

# --- STREAM API ---
def video_generator(filepath):
    tries = 0
    while not os.path.exists(filepath):
        asyncio.sleep(0.5)
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
    return StreamingResponse(video_generator(f"static/hls/{username}/stream.webm"), media_type="video/webm")

@router.post("/stream/restrict")
async def restrict(): return {"status": "ok"} 

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    streams = db.query(User).filter(User.is_live == True).all()
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "streams": streams, "broadcaster": None, "auction_active": False})

@router.post("/broadcast/start")
async def start(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.is_live = True; db.commit()
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

@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    
    # Kimlik (Basit)
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
        username = user.username
    except: 
        await websocket.close()
        return

    # Dosya Hazırlığı
    stream_dir = f"static/hls/{username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)
    
    file_handle = open(f"{stream_dir}/stream.webm", "wb")
    print(f"🎥 YAYIN BAŞLIYOR: {username}")

    try:
        packet_num = 0
        while True:
            # 20 saniye bekle
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=20.0)
            if not data: break
            
            file_handle.write(data)
            file_handle.flush()
            
            packet_num += 1
            if packet_num % 5 == 0:
                print(f"📥 SERVER ALDI: {len(data)} byte (Pkt: {packet_num})")
            
    except asyncio.TimeoutError:
        print(f"⚠️ SERVER: Timeout - {username}")
    except Exception as e:
        print(f"❌ SERVER HATASI: {e}")
    finally:
        file_handle.close()
        cleanup_stream(username)