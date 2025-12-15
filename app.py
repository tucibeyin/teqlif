import os
import subprocess
import asyncio
import json
import random
import requests
import base64
import shutil
import sys
from datetime import datetime, timedelta
from typing import Optional, List, Dict

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect, Depends, Form, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse 
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.security import OAuth2PasswordBearer

# VERİTABANI
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Boolean, Table, ForeignKey, desc
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
from passlib.context import CryptContext
from jose import JWTError, jwt

app = FastAPI()

# --- AYARLAR ---
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
if not SQLALCHEMY_DATABASE_URL: raise ValueError("DATABASE_URL yok!")
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY: raise ValueError("SECRET_KEY yok!")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 

# --- BAŞLANGIÇ TEMİZLİĞİ ---
try:
    if os.path.exists("static/hls"):
        shutil.rmtree("static/hls", ignore_errors=True)
except Exception as e:
    print(f"⚠️ Başlangıç temizliği uyarısı: {e}")

os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/css", exist_ok=True)
os.makedirs("static/thumbnails", exist_ok=True)

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# --- VERİTABANI MODELİ ---
engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Takipçiler Tablosu
followers_table = Table('followers', Base.metadata,
    Column('follower_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('followed_id', Integer, ForeignKey('users.id'), primary_key=True)
)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String)
    verification_code = Column(String)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Yayın Durumları
    is_live = Column(Boolean, default=False)       
    is_auction_active = Column(Boolean, default=False)
    stream_title = Column(String, default="")      
    thumbnail = Column(String, default="")
    
    # Kalıcı Mezat Durumu
    current_price = Column(Integer, default=0)
    highest_bidder = Column(String, nullable=True)

    # Takip İlişkisi
    followed = relationship(
        "User", 
        secondary=followers_table,
        primaryjoin=(followers_table.c.follower_id == id),
        secondaryjoin=(followers_table.c.followed_id == id),
        backref="followers"
    )

# Sohbet ve Teklif Geçmişi
class StreamMessage(Base):
    __tablename__ = "stream_messages"
    id = Column(Integer, primary_key=True, index=True)
    room_name = Column(String, index=True)
    sender = Column(String)
    message = Column(String)
    is_bid = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try: yield db
    finally: db.close()

# --- GÜVENLİK ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def verify_password(plain, hashed): return pwd_context.verify(plain, hashed)
def get_password_hash(password): return pwd_context.hash(password)
def create_access_token(data: dict):
    to_encode = data.copy()
    to_encode.update({"exp": datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(request: Request, db: Session = Depends(get_db)):
    token = request.cookies.get("access_token")
    if not token: return None
    try:
        scheme, _, param = token.partition(" ")
        payload = jwt.decode(param, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub")
        if email is None: return None
    except JWTError: return None
    return db.query(User).filter(User.email == email).first()

# --- MAİL & BİLDİRİM ---
def send_brevo_email(to_email, subject, html_content):
    try:
        url = "https://api.brevo.com/v3/smtp/email"
        headers = {"accept": "application/json", "api-key": os.getenv("BREVO_API_KEY"), "content-type": "application/json"}
        data = {"sender": {"name": "Teqlif", "email": os.getenv("SENDER_EMAIL")}, "to": [{"email": to_email}], "subject": subject, "htmlContent": html_content}
        requests.post(url, json=data, headers=headers)
    except: pass

def send_welcome_email(to_email):
    send_brevo_email(to_email, "Hoş Geldiniz!", "<p>Hesabınız onaylandı.</p>")

def notify_followers(user: User):
    followers_list = user.followers
    if not followers_list: return
    print(f"🔔 BİLDİRİM: {len(followers_list)} takipçiye haber veriliyor...")
    for follower in followers_list:
        html = f"<h1>{user.username} CANLI YAYINDA! 🔴</h1><p>Hemen katıl ve mezatı kaçırma!</p><a href='https://teqlif.com/live?mode=watch&broadcaster={user.username}'>İzlemek için tıkla</a>"
        send_brevo_email(follower.email, f"🔴 {user.username} Yayında!", html)

# --- SOCKET YÖNETİCİSİ ---
class ConnectionManager:
    def __init__(self):
        self.rooms: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, room_name: str):
        await websocket.accept()
        if room_name not in self.rooms: self.rooms[room_name] = []
        self.rooms[room_name].append(websocket)
        await self.broadcast_count(room_name)

    async def disconnect(self, websocket: WebSocket, room_name: str):
        if room_name in self.rooms:
            if websocket in self.rooms[room_name]: self.rooms[room_name].remove(websocket)
            await self.broadcast_count(room_name)
            if not self.rooms[room_name]: del self.rooms[room_name]

    async def broadcast_count(self, room_name: str):
        if room_name in self.rooms:
            count = len(self.rooms[room_name])
            msg = json.dumps({"type": "count", "val": count})
            for conn in self.rooms[room_name][:]:
                try: await conn.send_text(msg)
                except: pass

    async def broadcast_to_room(self, message: str, room_name: str):
        if room_name in self.rooms:
            for conn in self.rooms[room_name][:]:
                try: await conn.send_text(message)
                except: pass

manager = ConnectionManager()

# --- TEMİZLİK ROBOTU ---
active_processes: Dict[str, subprocess.Popen] = {}

def cleanup_stream(username: str, db: Session):
    print(f"🧹 TEMİZLİK: {username}")
    try:
        user = db.query(User).filter(User.username == username).first()
        if user:
            user.is_live = False
            user.is_auction_active = False
            # Yayın bitince bilgileri sıfırla
            user.current_price = 0
            user.highest_bidder = None
            db.commit() 
            # Geçmişi sil
            db.query(StreamMessage).filter(StreamMessage.room_name == username).delete()
            db.commit() 
    except Exception as e: 
        print(f"Temizlik hatası: {e}")

    if username in active_processes:
        proc = active_processes[username]
        try: proc.terminate(); proc.wait(timeout=2)
        except: proc.kill()
        del active_processes[username]

    folder_path = f"static/hls/{username}"
    if os.path.exists(folder_path):
        shutil.rmtree(folder_path, ignore_errors=True)

# --- ROTALAR ---
@app.get("/", response_class=HTMLResponse)
async def read_home(request: Request, db: Session = Depends(get_db), user: Optional[User] = Depends(get_current_user)):
    active_streams = db.query(User).filter(User.is_live == True).all()
    if user:
        followed_ids = [u.id for u in user.followed]
        active_streams.sort(key=lambda x: x.id not in followed_ids)
    return templates.TemplateResponse("index.html", {"request": request, "user": user, "streams": active_streams})

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request): 
    return templates.TemplateResponse("login.html", {"request": request})

@app.get("/signup", response_class=HTMLResponse)
async def signup_page(request: Request): 
    return templates.TemplateResponse("signup.html", {"request": request})

@app.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: Optional[str] = None, user: Optional[User] = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    
    target_user = None
    is_following = False
    
    if broadcaster:
        target_user = db.query(User).filter(User.username == broadcaster).first()
        if target_user and target_user in user.followed: is_following = True

    if mode == "broadcast":
        return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": "broadcast", "streams": [], "auction_active": user.is_auction_active})
    else:
        active_streams = db.query(User).filter(User.is_live == True).all()
        followed_ids = [u.id for u in user.followed]
        active_streams.sort(key=lambda x: (x.username == broadcaster, x.id in followed_ids), reverse=True)
        return templates.TemplateResponse("live.html", {
            "request": request, 
            "user": user, 
            "mode": "watch", 
            "streams": active_streams, 
            "auction_active": target_user.is_auction_active if target_user else False,
            "is_following": is_following,
            "broadcaster": target_user
        })

@app.post("/auth/signup")
async def signup(request: Request, email: str = Form(...), password: str = Form(...), password_confirm: str = Form(...), db: Session = Depends(get_db)):
    if password != password_confirm: return templates.TemplateResponse("signup.html", {"request": request, "error": "Şifreler uyuşmuyor."})
    if db.query(User).filter(User.email == email).first(): return templates.TemplateResponse("signup.html", {"request": request, "error": "Kayıtlı email."})
    new_user = User(email=email, password_hash=get_password_hash(password), verification_code=str(random.randint(100000, 999999)))
    db.add(new_user); db.commit()
    send_brevo_email(email, "Doğrulama Kodu", f"<h1>{new_user.verification_code}</h1>")
    return RedirectResponse(url=f"/verify?email={email}", status_code=303)

@app.get("/verify", response_class=HTMLResponse)
async def verify_page(request: Request, email: str): return templates.TemplateResponse("verify.html", {"request": request, "email": email})

@app.post("/auth/verify")
async def verify_code(request: Request, email: str = Form(...), code: str = Form(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    if not user or user.verification_code != code: return templates.TemplateResponse("verify.html", {"request": request, "email": email, "error": "Hata."})
    user.is_verified = True; db.commit(); send_welcome_email(email)
    return RedirectResponse(url="/login?msg=verified", status_code=303)

@app.post("/auth/login")
async def login(request: Request, email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(password, user.password_hash): return templates.TemplateResponse("login.html", {"request": request, "error": "Hatalı bilgi."})
    if not user.is_verified: return templates.TemplateResponse("login.html", {"request": request, "error": "Hesabınız onaylanmamış."})
    resp = RedirectResponse(url="/", status_code=303)
    resp.set_cookie(key="access_token", value=f"Bearer {create_access_token({'sub': user.email})}", httponly=True)
    return resp

@app.get("/logout")
async def logout():
    resp = RedirectResponse(url="/", status_code=303)
    resp.delete_cookie("access_token")
    return resp

@app.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, user: Optional[User] = Depends(get_current_user)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    return templates.TemplateResponse("settings.html", {"request": request, "user": user})

@app.post("/settings/update")
async def update_profile(request: Request, username: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    if db.query(User).filter(User.username == username).first() and user.username != username:
        return templates.TemplateResponse("settings.html", {"request": request, "user": user, "error": "Kullanıcı adı dolu."})
    user.username = username; db.commit()
    return templates.TemplateResponse("settings.html", {"request": request, "user": user, "success": "Güncellendi."})

@app.post("/user/follow")
async def follow_user(username: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return JSONResponse({"status": "error"}, 401)
    target = db.query(User).filter(User.username == username).first()
    if not target or target.id == user.id: return JSONResponse({"status": "error"}, 400)
    
    if target not in user.followed:
        user.followed.append(target); db.commit(); return JSONResponse({"status": "followed"})
    else:
        user.followed.remove(target); db.commit(); return JSONResponse({"status": "unfollowed"})

@app.post("/broadcast/start")
async def start_broadcast_api(title: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_live = True; user.stream_title = title; db.commit()
    notify_followers(user)
    return {"status": "success"}

@app.post("/broadcast/stop")
async def stop_broadcast_api(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    cleanup_stream(user.username, db)
    return {"status": "stopped"}

@app.post("/broadcast/toggle_auction")
async def toggle_auction(active: bool = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_auction_active = active
    db.commit()
    msg = json.dumps({"type": "auction_state", "active": active})
    await manager.broadcast_to_room(msg, user.username) 
    await manager.broadcast_to_room(msg, "broadcast")   
    return {"status": "ok", "active": active}

@app.post("/broadcast/thumbnail")
async def upload_thumbnail(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    try:
        data = await request.json()
        image_data = data['image'].split(",")[1]
        filename = f"thumb_{user.username}.jpg"
        file_path = f"static/thumbnails/{filename}"
        with open(file_path, "wb") as f: f.write(base64.b64decode(image_data))
        user.thumbnail = f"/static/thumbnails/{filename}?t={data['timestamp']}"
        db.commit()
        return {"status": "ok"}
    except: return {"status": "error"}

@app.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket, stream: str = "general", db: Session = Depends(get_db)):
    room_name = stream
    await manager.connect(websocket, room_name)
    
    current_username = "Misafir"
    try:
        token = websocket.cookies.get("access_token")
        if token:
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            u = db.query(User).filter(User.email == payload.get("sub")).first()
            if u: current_username = u.username
    except: pass

    broadcaster = db.query(User).filter(User.username == stream).first()
    if broadcaster:
        init_msg = json.dumps({
            "type": "init",
            "price": broadcaster.current_price,
            "leader": broadcaster.highest_bidder
        })
        await websocket.send_text(init_msg)

        last_msgs = db.query(StreamMessage).filter(StreamMessage.room_name == stream)\
                      .order_by(desc(StreamMessage.created_at)).limit(30).all()
        for msg in reversed(last_msgs):
            hist_payload = json.dumps({
                "type": "chat",
                "user": msg.sender,
                "msg": msg.message
            })
            await websocket.send_text(hist_payload)

    try:
        while True:
            data = await websocket.receive_text()
            if data.strip():
                is_bid = data.startswith("BID:")
                new_msg = StreamMessage(
                    room_name=stream,
                    sender=current_username,
                    message=data.replace("<", "&lt;"),
                    is_bid=is_bid
                )
                db.add(new_msg)
                
                if is_bid and broadcaster:
                    try:
                        amount = int(data.split(":")[1])
                        if amount > broadcaster.current_price:
                            broadcaster.current_price = amount
                            broadcaster.highest_bidder = current_username
                    except: pass
                
                db.commit()
                msg_payload = json.dumps({"type": "chat", "user": current_username, "msg": data.replace("<", "&lt;")})
                await manager.broadcast_to_room(msg_payload, room_name)
    except: 
        await manager.disconnect(websocket, room_name)

@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    user = None
    try:
        token = websocket.cookies.get("access_token")
        if token:
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            user = db.query(User).filter(User.email == payload.get("sub")).first()
    except: pass

    if not user or not user.username: await websocket.close(); return

    stream_dir = f"static/hls/{user.username}"
    if os.path.exists(stream_dir):
        try: shutil.rmtree(stream_dir, ignore_errors=True)
        except: pass
    os.makedirs(stream_dir, exist_ok=True)
    
    stream_path = f"{stream_dir}/stream.m3u8"
    print(f"🎥 YAYIN BAŞLIYOR (ULTRA LOW LATENCY): {user.username}")

    # 🔥 DÜŞÜK GECİKME İÇİN OPTİMİZE EDİLMİŞ FFmpeg KOMUTU
    command = [
        "ffmpeg", "-f", "webm", "-fflags", "+genpts+igndts+nobuffer", "-i", "pipe:0",
        
        "-c:v", "libx264", 
        "-preset", "veryfast",  
        "-profile:v", "high",   
        "-tune", "zerolatency", 
        
        "-threads", "0", 
        "-r", "30",             
        "-g", "30",             # 🔥 Keyframe her 1 saniyede bir (Gecikmeyi düşürür)
        
        "-b:v", "2500k", "-maxrate", "3000k", "-bufsize", "3000k", 
        "-pix_fmt", "yuv420p",
        
        "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2", "-af", "aresample=async=1000",
        
        "-f", "hls", 
        "-hls_time", "1",       # 🔥 Parçalar 1 saniyelik olacak
        "-hls_list_size", "4",  # Liste boyutu 4
        "-hls_flags", "delete_segments+append_list+omit_endlist+discont_start", 
        "-hls_segment_type", "mpegts",
        
        "-max_muxing_queue_size", "1024", "-loglevel", "error", 
        stream_path 
    ]
    
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=sys.stderr)
    active_processes[user.username] = process

    try:
        while True:
            data = await websocket.receive_bytes()
            if process.stdin:
                try: process.stdin.write(data); process.stdin.flush()
                except BrokenPipeError: break
    except Exception as e: print(f"❌ Yayın Hatası: {e}")
    finally:
        print(f"🔌 Yayın Bitti: {user.username}")
        cleanup_stream(user.username, db)