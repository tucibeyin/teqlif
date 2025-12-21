import os
import json
import shutil
import subprocess
import asyncio 
import signal
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
async def client_log(request: Request): return {"status": "ok"}

# --- MANAGER ---
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

# 🔥 ASENKRON VE ACIMASIZ TEMİZLİK 🔥
def cleanup_stream_sync(username):
    """
    Bu fonksiyon arka planda çalışır, sunucuyu kilitlemez.
    FFmpeg işlemini anında öldürür.
    """
    print(f"🛑 SERVER: {username} temizleniyor (NON-BLOCKING)...")
    
    # 1. FFmpeg'i Öldür (Beklemek yok!)
    if username in active_processes:
        proc = active_processes[username]
        try:
            proc.kill() # Terminate değil, KILL (Zorla kapat)
            proc.wait(timeout=0.1) # Sadece 0.1sn bekle, ölüsünü kaldır
        except: pass
        del active_processes[username]
    
    # 2. Veritabanını Güncelle
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: 
            u.is_live = False
            db.commit()
    except Exception as e:
        print(f"DB Temizlik Hatası: {e}")
    finally:
        db.close()

async def cleanup_stream_async(username):
    """Cleanup işlemini ana thread'i bloklamadan çalıştırır"""
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, cleanup_stream_sync, username)

def write_to_ffmpeg(process, data):
    """Veriyi FFmpeg'e yazar, hata verirse sessizce geçer"""
    if process and process.stdin:
        try:
            process.stdin.write(data)
            process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass # İşlem ölmüşse zorlama

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
    user.is_live = True; user.stream_title = title; user.stream_category = category; db.commit()
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    # Stop isteği geldiğinde arka planda temizle, hemen cevap dön
    asyncio.create_task(cleanup_stream_async(user.username))
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
    except: pass
    return {"status": "ok"}
@router.post("/broadcast/toggle_auction")
async def toggle_auction(): return {"status": "ok"}
@router.post("/broadcast/reset_auction")
async def reset_auction(): return {"status": "ok"}
@router.post("/gift/send")
async def send_gift(): return {"status": "success"}
@router.websocket("/ws/chat")
async def chat(ws: WebSocket): await ws.accept()

# --- YAYINCI SOCKETİ ---
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

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir): shutil.rmtree(stream_dir)
    os.makedirs(stream_dir, exist_ok=True)

    print(f"🎥 TURBO YAYIN (Low Latency + Quick Kill): {user.username}")

    # 🔥 FFmpeg AYARLARI (TURBO MODE) 🔥
    command = [
        "ffmpeg", 
        "-f", "webm", 
        "-i", "pipe:0",
        
        "-c:v", "libx264", 
        "-preset", "ultrafast", 
        "-tune", "zerolatency", 
        "-r", "24", 
        "-b:v", "1500k", 
        "-vf", "scale=-2:540", 
        
        "-c:a", "aac", 
        "-b:a", "64k", 
        "-ac", "2", 
        
        "-f", "hls", 
        "-hls_time", "1", # 1 saniyelik segmentler
        "-hls_list_size", "5", 
        "-hls_flags", "delete_segments+omit_endlist+split_by_time",
        f"{stream_dir}/index.m3u8"
    ]
    
    # start_new_session=True: FFmpeg'i ayrı bir işlem grubunda başlatır (Daha kolay öldürülür)
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
    active_processes[user.username] = process
    
    # Bildirim
    async def notify():
        await asyncio.sleep(2) 
        new_db = SessionLocal()
        u = new_db.query(User).filter(User.username == user.username).first()
        u.is_live = True; new_db.commit(); new_db.close()
        await manager.broadcast_to_room(json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""}), "home")
    
    loop = asyncio.get_event_loop()
    loop.create_task(notify())

    try:
        while True:
            # 10 saniye veri gelmezse döngüyü kır
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=10.0)
            if not data: break
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
    except Exception as e:
        print(f"Yayın Kesildi: {e}")
    finally:
        # 🔥 KRİTİK: BURASI KİLİTLEMEYECEK 🔥
        # Temizliği asenkron görev olarak başlat ve hemen çık
        asyncio.create_task(cleanup_stream_async(user.username))
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")