import os
import json
import shutil
import subprocess
import sys
import asyncio 
import time
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user, SECRET_KEY, ALGORITHM

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- Loglama ---
@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"📱 [CLIENT] {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- Socket Manager ---
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
active_processes = {}

def cleanup_stream(username):
    print(f"🛑 SERVER: {username} temizleniyor...")
    if username in active_processes:
        proc = active_processes[username]
        try:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=2)
        except: 
            try: proc.kill()
            except: pass
        if username in active_processes: del active_processes[username]
    
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; u.is_auction_active = False; db.commit()
    except: pass
    finally: db.close()

def write_to_ffmpeg(process, data):
    if process and process.stdin:
        try:
            process.stdin.write(data)
            process.stdin.flush()
        except Exception as e:
            print(f"❌ FFmpeg Yazma Hatası: {e}")

# --- Routes ---
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
    os.makedirs(f"{stream_dir}", exist_ok=True)

    print(f"🎥 YAYIN BAŞLIYOR (DASH MODE): {user.username}")

    # 🔥 FFmpeg DASH COPY (CPU %1) 🔥
    # WebM formatını olduğu gibi DASH parçalarına böler.
    # Bu işlem CPU kullanmaz ve dosya yapısı düzgün olur.
    command = [
        "ffmpeg", 
        "-f", "webm", # Girdi formatı
        "-analyzeduration", "10000000", "-probesize", "10000000", 
        "-fflags", "+genpts+igndts+nobuffer+discardcorrupt",
        "-err_detect", "ignore_err",
        "-i", "pipe:0", # Girdi: WebSocket'ten gelen boru
        
        "-c", "copy", # Kopyala (İşleme yapma)
        
        "-f", "dash", # Çıktı: DASH (WebM uyumlu akış)
        "-window_size", "5", # Son 5 parça
        "-extra_window_size", "5",
        "-seg_duration", "3", # 3 saniyelik parçalar
        "-remove_at_exit", "1",
        f"{stream_dir}/stream.mpd" # Manifest dosyası
    ]
    
    # Logları sistem loguna bas
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr)
    active_processes[user.username] = process
    
    async def wait_for_stream():
        start_t = time.time()
        while time.time() - start_t < 30:
            if os.path.exists(f"{stream_dir}/stream.mpd"):
                print(f"✅ YAYIN AKTİF: {user.username}")
                new_db = SessionLocal()
                u = new_db.query(User).filter(User.username == user.username).first()
                u.is_live = True; new_db.commit(); new_db.close()
                payload = json.dumps({"type": "stream_added", "username": user.username, "title": "Canlı", "category": "Genel", "thumbnail": ""})
                await manager.broadcast_to_room(payload, "home")
                break
            await asyncio.sleep(0.5)

    loop = asyncio.get_event_loop()
    loop.create_task(wait_for_stream())

    try:
        while True:
            try:
                # 30 saniye veri gelmezse kapat
                data = await asyncio.wait_for(websocket.receive_bytes(), timeout=30.0)
                if not data: break
                
                # FFmpeg yaşıyor mu?
                if process.poll() is not None:
                    print(f"❌ FFmpeg Kapandı (Kod: {process.returncode})")
                    break

                await loop.run_in_executor(None, write_to_ffmpeg, process, data)
                
            except asyncio.TimeoutError:
                print(f"⚠️ SERVER: Timeout {user.username}")
                break 
    except Exception as e:
        print(f"❌ SERVER HATASI: {e}")
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")