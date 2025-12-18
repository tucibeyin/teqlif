import os
import json
import shutil
import subprocess
import sys
import base64
import asyncio 
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect, Depends, Form, BackgroundTasks
from fastapi.responses import RedirectResponse, HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User, StreamMessage, StreamRestriction
from utils import get_current_user, send_broadcast_notifications_task

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- SOCKET YÖNETİCİSİ ---
class ConnectionManager:
    def __init__(self):
        self.rooms: Dict[str, List[dict]] = {}
        
    async def connect(self, websocket: WebSocket, room_name: str, username: str):
        await websocket.accept()
        if room_name not in self.rooms: self.rooms[room_name] = []
        self.rooms[room_name].append({"ws": websocket, "user": username})
        if room_name != "home":
            await self.broadcast_count(room_name)

    async def disconnect(self, websocket: WebSocket, room_name: str):
        if room_name in self.rooms:
            self.rooms[room_name] = [c for c in self.rooms[room_name] if c["ws"] != websocket]
            if room_name != "home":
                await self.broadcast_count(room_name)
            if not self.rooms[room_name]: del self.rooms[room_name]

    async def broadcast_count(self, room_name: str):
        if room_name in self.rooms:
            count = len(self.rooms[room_name])
            msg = json.dumps({"type": "count", "val": count})
            for c in self.rooms[room_name]:
                try: await c["ws"].send_text(msg)
                except: pass

    async def broadcast_to_room(self, message: str, room_name: str):
        if room_name in self.rooms:
            for c in self.rooms[room_name]:
                try: await c["ws"].send_text(message)
                except: pass
    
    async def kick_user(self, room_name: str, username: str):
        if room_name in self.rooms:
            targets = [c for c in self.rooms[room_name] if c["user"] == username]
            for t in targets:
                try:
                    await t["ws"].send_text(json.dumps({"type": "banned"}))
                    await t["ws"].close()
                except: pass
            self.rooms[room_name] = [c for c in self.rooms[room_name] if c["user"] != username]
            await self.broadcast_count(room_name)

manager = ConnectionManager()
active_processes: Dict[str, subprocess.Popen] = {}

# --- YARDIMCI: TEMİZLİK (Garanti Yöntem) ---
def cleanup_stream(username: str):
    # 1. FFmpeg Sürecini Öldür
    if username in active_processes:
        proc = active_processes[username]
        try: proc.terminate(); proc.wait(timeout=2)
        except: proc.kill()
        del active_processes[username]

    # 2. Veritabanını Temizle (Kendi Session'ını Açar)
    # Bu, websocket kopsa bile DB işleminin yapılmasını garanti eder.
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == username).first()
        if user:
            user.is_live = False
            user.is_auction_active = False
            user.current_price = 0
            user.highest_bidder = None
            db.commit()
    except Exception as e:
        print(f"Cleanup DB Error: {e}")
    finally:
        db.close()

    # 3. Dosyaları Sil
    try: shutil.rmtree(f"static/hls/{username}", ignore_errors=True)
    except: pass

def write_to_ffmpeg(process, data):
    try:
        if process.stdin: process.stdin.write(data); process.stdin.flush()
    except: pass

# --- API ENDPOINTLERİ ---
@router.post("/stream/restrict")
async def restrict_user(target_username: str = Form(...), action: str = Form(...), duration: int = Form(0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user or not user.is_live: return JSONResponse({"status": "error", "msg": "Yetkisiz"}, 403)
    room_name = user.username
    db.query(StreamRestriction).filter(StreamRestriction.room_name == room_name, StreamRestriction.user_username == target_username).delete()
    if action == "unban": db.commit(); return {"status": "success", "msg": "Kaldırıldı"}
    expires = datetime.utcnow() + timedelta(minutes=duration) if duration > 0 else None
    db.add(StreamRestriction(room_name=room_name, user_username=target_username, type=action, expires_at=expires))
    db.commit()
    if action == "ban": await manager.kick_user(room_name, target_username)
    return {"status": "success", "msg": f"{target_username} {action}"}

@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: Optional[str] = None, user: Optional[User] = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    target_user = None; is_following = False; db.refresh(user)
    if broadcaster:
        target_user = db.query(User).filter(User.username == broadcaster).first()
        if target_user and target_user in user.followed: is_following = True
        if db.query(StreamRestriction).filter(StreamRestriction.room_name == broadcaster, StreamRestriction.user_username == user.username, StreamRestriction.type == 'ban').first():
             return templates.TemplateResponse("base.html", {"request": request, "user": user, "error": "Yasaklandınız!"})
    if mode == "broadcast": return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": "broadcast", "streams": [], "auction_active": user.is_auction_active})
    else:
        active_streams = db.query(User).filter(User.is_live == True, User.username != None).all()
        return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": "watch", "streams": active_streams, "auction_active": target_user.is_auction_active if target_user else False, "is_following": is_following, "broadcaster": target_user})

@router.post("/gift/send")
async def send_gift(target_username: str = Form(...), gift_type: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return JSONResponse({"status": "error", "msg": "Giriş yapın"}, 401)
    target = db.query(User).filter(User.username == target_username).first()
    if not target: return JSONResponse({"status": "error", "msg": "Kullanıcı yok"}, 404)
    prices = {"rose": 10, "heart": 50, "car": 500, "rocket": 5000}
    cost = prices.get(gift_type, 0)
    if user.diamonds < cost: return JSONResponse({"status": "error", "msg": "Yetersiz Elmas!"}, 400)
    user.diamonds -= cost; target.diamonds += cost
    msg_entry = StreamMessage(room_name=target_username, sender=user.username, message=f"{gift_type} gönderdi!", is_gift=True, gift_type=gift_type)
    db.add(msg_entry); db.commit()
    payload = json.dumps({"type": "gift", "sender": user.username, "gift_type": gift_type, "amount": cost})
    await manager.broadcast_to_room(payload, target_username); await manager.broadcast_to_room(payload, "broadcast")
    return JSONResponse({"status": "success", "new_balance": user.diamonds})

@router.post("/broadcast/start")
async def start_broadcast_api(background_tasks: BackgroundTasks, title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.stream_title = title; user.stream_category = category; user.is_live = False; db.commit()
    emails = [f.email for f in user.followers]; background_tasks.add_task(send_broadcast_notifications_task, emails, user.username)
    return {"status": "success"}

@router.post("/broadcast/stop")
async def stop_broadcast_api(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    cleanup_stream(user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
    await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")
    return {"status": "stopped"}

@router.post("/broadcast/toggle_auction")
async def toggle_auction(active: bool = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_auction_active = active; db.commit()
    msg = json.dumps({"type": "auction_state", "active": active})
    await manager.broadcast_to_room(msg, user.username); await manager.broadcast_to_room(msg, "broadcast")
    return {"status": "ok", "active": active}

@router.post("/broadcast/reset_auction")
async def reset_auction(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.current_price = 0; user.highest_bidder = None; db.commit()
    msg = json.dumps({"type": "reset_auction", "price": 0, "leader": None})
    await manager.broadcast_to_room(msg, user.username); await manager.broadcast_to_room(msg, "broadcast")
    return {"status": "ok"}

@router.post("/broadcast/thumbnail")
async def upload_thumbnail(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    try:
        data = await request.json()
        image_data = data['image'].split(",")[1]; filename = f"thumb_{user.username}.jpg"
        with open(f"static/thumbnails/{filename}", "wb") as f: f.write(base64.b64decode(image_data))
        user.thumbnail = f"/static/thumbnails/{filename}?t={data['timestamp']}"; db.commit()
        return {"status": "ok"}
    except: return {"status": "error"}

@router.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket, stream: str = "general", db: Session = Depends(get_db)):
    room_name = stream; await manager.connect(websocket, room_name, "Misafir"); current_username = "Misafir"
    try:
        token = websocket.cookies.get("access_token")
        if token:
            from jose import jwt
            from utils import SECRET_KEY, ALGORITHM
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            u = db.query(User).filter(User.email == payload.get("sub")).first()
            if u: current_username = u.username
            if room_name in manager.rooms:
                for c in manager.rooms[room_name]:
                    if c["ws"] == websocket: c["user"] = current_username
    except: pass
    
    if room_name != "home":
        if db.query(StreamRestriction).filter(StreamRestriction.room_name == room_name, StreamRestriction.user_username == current_username, StreamRestriction.type == 'ban').first():
            await websocket.send_text(json.dumps({"type": "banned"})); await websocket.close(); return

    if room_name == "home":
        try:
            while True: await websocket.receive_text()
        except: await manager.disconnect(websocket, room_name); return

    broadcaster = db.query(User).filter(User.username == stream).first()
    if broadcaster: await websocket.send_text(json.dumps({"type": "init", "price": broadcaster.current_price, "leader": broadcaster.highest_bidder}))
    
    try:
        while True:
            data = await websocket.receive_text()
            if data.strip():
                res = db.query(StreamRestriction).filter(StreamRestriction.room_name == room_name, StreamRestriction.user_username == current_username, StreamRestriction.type == 'mute').first()
                if res:
                    if res.expires_at and res.expires_at < datetime.utcnow(): db.delete(res); db.commit()
                    else: await websocket.send_text(json.dumps({"type": "alert", "msg": "🚫 Susturuldunuz!"})); continue

                is_bid = data.startswith("BID:"); safe_msg = data.replace("<", "&lt;")
                new_msg = StreamMessage(room_name=stream, sender=current_username, message=safe_msg, is_bid=is_bid); db.add(new_msg)
                if is_bid and broadcaster:
                    try:
                        amount = int(data.split(":")[1])
                        if amount > broadcaster.current_price: broadcaster.current_price = amount; broadcaster.highest_bidder = current_username; db.add(broadcaster)
                    except: pass
                db.commit(); await manager.broadcast_to_room(json.dumps({"type": "chat", "user": current_username, "msg": safe_msg}), room_name)
    except: await manager.disconnect(websocket, room_name)

@router.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    user = None
    try:
        token = websocket.cookies.get("access_token")
        if token:
            from jose import jwt
            from utils import SECRET_KEY, ALGORITHM
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: pass
    if not user or not user.username: await websocket.close(); return

    stream_dir = f"static/hls/{user.username}"
    shutil.rmtree(stream_dir, ignore_errors=True)
    os.makedirs(f"{stream_dir}/720p", exist_ok=True); os.makedirs(f"{stream_dir}/480p", exist_ok=True)
    os.makedirs(f"{stream_dir}/360p", exist_ok=True); os.makedirs(f"{stream_dir}/240p", exist_ok=True)
    
    print(f"🎥 YAYIN (ULTIMATE + ANDROID FIXED): {user.username}")

    command = [
        "ffmpeg", 
        # --- GİRİŞ AYARLARI (Android Uyumluluğu) ---
        "-f", "matroska",  # WebM yerine Matroska (Daha toleranslı)
        "-use_wallclock_as_timestamps", "1", # Zaman damgası hatasını yoksay
        "-analyzeduration", "5000000", # Hızlı analiz (5sn)
        "-probesize", "5000000",
        "-fflags", "+genpts+igndts+nobuffer+discardcorrupt", 
        "-err_detect", "ignore_err",
        "-i", "pipe:0",
        
        # --- FİLTRE VE ÖLÇEKLENDİRME ---
        "-filter_complex", 
        "[0:v]scale=-2:720,crop=406:720:(in_w-406)/2:0,split=4[v720][v480][v360][v240];"
        "[v720]copy[out720];"
        "[v480]scale=270:-2[out480];"
        "[v360]scale=202:-2[out360];"
        "[v240]scale=136:-2[out240]",
        
        # --- PERFORMANS VE LATENCY ---
        "-preset", "ultrafast",  # En hızlı sıkıştırma (CPU dostu)
        "-tune", "zerolatency",  # Gecikme yok
        "-threads", "0", 
        
        "-profile:v", "baseline", "-level", "3.0", 
        "-g", "30", # Keyframe her 1 saniyede (30fps x 1s)
        "-pix_fmt", "yuv420p",

        # --- ÇIKTI AYARLARI (4 Kalite) ---
        "-map", "[out720]", "-map", "0:a", "-c:v:0", "libx264", "-b:v:0", "2000k", "-maxrate:v:0", "2500k", "-bufsize:v:0", "3000k", "-c:a:0", "aac", "-b:a:0", "128k",
        "-map", "[out480]", "-map", "0:a", "-c:v:1", "libx264", "-b:v:1", "1000k", "-maxrate:v:1", "1200k", "-bufsize:v:1", "1500k", "-c:a:1", "aac", "-b:a:1", "96k",
        "-map", "[out360]", "-map", "0:a", "-c:v:2", "libx264", "-b:v:2", "600k", "-maxrate:v:2", "800k", "-bufsize:v:2", "1000k", "-c:a:2", "aac", "-b:a:2", "64k",
        "-map", "[out240]", "-map", "0:a", "-c:v:3", "libx264", "-b:v:3", "300k", "-maxrate:v:3", "400k", "-bufsize:v:3", "500k", "-c:a:3", "aac", "-b:a:3", "48k",
        
        # --- HLS PAKETLEME (Low Latency) ---
        "-f", "hls", 
        "-hls_time", "1",       # 1 Saniyelik parçalar (Gecikmeyi düşürür)
        "-hls_list_size", "3",  # Listede sadece 3 saniye tut (Geriden gelmeyi engeller)
        "-hls_flags", "delete_segments+omit_endlist+discont_start+program_date_time", 
        "-hls_allow_cache", "0",
        "-var_stream_map", "v:0,a:0,name:720p v:1,a:1,name:480p v:2,a:2,name:360p v:3,a:3,name:240p",
        "-master_pl_name", "master.m3u8", f"{stream_dir}/%v/stream.m3u8"
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr)
    active_processes[user.username] = process
    
    async def wait_for_file_and_go_live(username, title, category, thumbnail):
        master_file = f"static/hls/{username}/master.m3u8"
        start_wait = time.time()
        while time.time() - start_wait < 30: # 30sn bekleme
            if os.path.exists(master_file):
                new_db = SessionLocal()
                try:
                    u = new_db.query(User).filter(User.username == username).first()
                    if u: 
                        u.is_live = True; new_db.commit()
                        payload = json.dumps({"type": "stream_added", "username": username, "title": title, "category": category, "thumbnail": thumbnail})
                        await manager.broadcast_to_room(payload, "home")
                except: pass
                finally: new_db.close()
                break
            await asyncio.sleep(0.5)

    loop = asyncio.get_event_loop()
    loop.create_task(wait_for_file_and_go_live(user.username, user.stream_title, user.stream_category, user.thumbnail))

    try:
        while True:
            data = await websocket.receive_bytes()
            await loop.run_in_executor(None, write_to_ffmpeg, process, data)
    except: pass
    finally:
        cleanup_stream(user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_ended"}), user.username)
        await manager.broadcast_to_room(json.dumps({"type": "stream_removed", "username": user.username}), "home")