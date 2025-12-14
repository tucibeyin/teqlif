import os
import subprocess
import asyncio
import json
import random
import requests
import base64
from datetime import datetime, timedelta
from typing import Optional, List

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect, Depends, Form, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.security import OAuth2PasswordBearer

# VERİTABANI
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
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

# Klasör Temizlik ve Hazırlık
os.system("rm -rf static/hls/*")
os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/css", exist_ok=True)
os.makedirs("static/thumbnails", exist_ok=True)

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# --- VERİTABANI MODELİ ---
engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String)
    verification_code = Column(String)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # --- YENİ EKLENEN VİTRİN ÖZELLİKLERİ ---
    is_live = Column(Boolean, default=False)       
    stream_title = Column(String, default="")      
    thumbnail = Column(String, default="")         

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

# --- MAİL FONKSİYONLARI ---
def send_brevo_email(to_email, code):
    try:
        url = "https://api.brevo.com/v3/smtp/email"
        headers = {"accept": "application/json", "api-key": os.getenv("BREVO_API_KEY"), "content-type": "application/json"}
        data = {"sender": {"name": "Teqlif", "email": os.getenv("SENDER_EMAIL")}, "to": [{"email": to_email}], "subject": "Doğrulama Kodu", "htmlContent": f"<h1>{code}</h1>"}
        requests.post(url, json=data, headers=headers)
    except: pass

def send_welcome_email(to_email):
    try:
        url = "https://api.brevo.com/v3/smtp/email"
        headers = {"accept": "application/json", "api-key": os.getenv("BREVO_API_KEY"), "content-type": "application/json"}
        data = {"sender": {"name": "Teqlif", "email": os.getenv("SENDER_EMAIL")}, "to": [{"email": to_email}], "subject": "Hoş Geldiniz!", "htmlContent": "<p>Hesabınız onaylandı.</p>"}
        requests.post(url, json=data, headers=headers)
    except: pass

# --- WEBSOCKET MANAGER (BU EKSİKTİ!) ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
    async def broadcast(self, message: str):
        for connection in self.active_connections:
            await connection.send_text(message)

# --- ROTALAR ---

@app.get("/", response_class=HTMLResponse)
async def read_home(request: Request, db: Session = Depends(get_db), user: Optional[User] = Depends(get_current_user)):
    active_streams = db.query(User).filter(User.is_live == True).all()
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "user": user, 
        "streams": active_streams
    })

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request): return templates.TemplateResponse("login.html", {"request": request})

@app.get("/signup", response_class=HTMLResponse)
async def signup_page(request: Request): return templates.TemplateResponse("signup.html", {"request": request})

@app.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, user: Optional[User] = Depends(get_current_user)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    return templates.TemplateResponse("live.html", {"request": request, "user": user})

@app.post("/auth/signup")
async def signup(request: Request, email: str = Form(...), password: str = Form(...), password_confirm: str = Form(...), db: Session = Depends(get_db)):
    if password != password_confirm: return templates.TemplateResponse("signup.html", {"request": request, "error": "Şifreler uyuşmuyor."})
    if db.query(User).filter(User.email == email).first(): return templates.TemplateResponse("signup.html", {"request": request, "error": "Kayıtlı email."})
    
    new_user = User(email=email, password_hash=get_password_hash(password), verification_code=str(random.randint(100000, 999999)))
    db.add(new_user); db.commit()
    send_brevo_email(email, new_user.verification_code)
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
    if not user.is_verified: return templates.TemplateResponse("login.html", {"request": request, "error": "Onaylayın."})
    
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

@app.post("/broadcast/start")
async def start_broadcast_api(title: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_live = True; user.stream_title = title; db.commit()
    return {"status": "success"}

@app.post("/broadcast/stop")
async def stop_broadcast_api(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return {"status": "error"}
    user.is_live = False; db.commit()
    return {"status": "stopped"}

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

manager = ConnectionManager()
@app.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await manager.connect(websocket)
    username = "Misafir"
    try:
        token = websocket.cookies.get("access_token")
        if token:
            payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
            user = db.query(User).filter(User.email == payload.get("sub")).first()
            if user: username = user.username if user.username else user.email.split("@")[0]
    except: pass
    
    try:
        while True:
            data = await websocket.receive_text()
            if data.strip(): await manager.broadcast(json.dumps({"user": username, "msg": data.replace("<", "&lt;")}))
    except: manager.disconnect(websocket)

stream_process = None
@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket):
    global stream_process
    await websocket.accept()
    
    command = [
        "ffmpeg", "-i", "pipe:0", "-c:v", "libx264", "-preset", "superfast", "-tune", "zerolatency",
        "-b:v", "2500k", "-maxrate", "3000k", "-bufsize", "6000k", "-vf", "scale=1280:-2", "-g", "60",
        "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-f", "hls", "-hls_time", "2",
        "-hls_list_size", "3", "-hls_flags", "delete_segments+append_list", "static/hls/stream.m3u8"
    ]
    stream_process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        while True:
            data = await websocket.receive_bytes()
            if stream_process and stream_process.stdin: stream_process.stdin.write(data); stream_process.stdin.flush()
    except: 
        if stream_process: stream_process.terminate()