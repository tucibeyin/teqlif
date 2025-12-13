import os
import subprocess
import asyncio
from datetime import datetime, timedelta
from typing import Optional, List

# --- .ENV YÜKLEME ---
from dotenv import load_dotenv
load_dotenv() # .env dosyasındaki şifreleri okur

from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect, Depends, Form, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.security import OAuth2PasswordBearer

# --- VERİTABANI & GÜVENLİK ---
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from passlib.context import CryptContext
from jose import JWTError, jwt

app = FastAPI()

# ==========================================
# 1. AYARLAR (CONFIG)
# ==========================================

# Veritabanı URL'si (.env dosyasından gelir)
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
if not SQLALCHEMY_DATABASE_URL:
    raise ValueError("HATA: .env dosyasında DATABASE_URL bulunamadı!")

# Gizli Anahtar (.env dosyasından gelir)
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise ValueError("HATA: .env dosyasında SECRET_KEY bulunamadı!")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 # 24 Saat

# Klasör Temizliği ve Hazırlığı
os.system("rm -rf static/hls/*")
os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/css", exist_ok=True)

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# ==========================================
# 2. VERİTABANI MODELLEMESİ
# ==========================================
engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False) # Zorunlu
    username = Column(String, unique=True, index=True, nullable=True) # BOŞ OLABİLİR
    password_hash = Column(String)
    verification_code = Column(String)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

# Tabloları oluştur
Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ==========================================
# 3. GÜVENLİK (AUTH)
# ==========================================
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(request: Request, db: Session = Depends(get_db)):
    token = request.cookies.get("access_token")
    if not token: return None
    try:
        scheme, _, param = token.partition(" ")
        payload = jwt.decode(param, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub") # Username yerine email okuyoruz
        if email is None: return None
    except JWTError:
        return None
    
    # DB'den email ile bul
    user = db.query(User).filter(User.email == email).first()
    return user

# ==========================================
# 4. ROTALAR (ROUTES)
# ==========================================

# Ana Sayfa
@app.get("/", response_class=HTMLResponse)
async def read_home(request: Request, user: Optional[User] = Depends(get_current_user)):
    return templates.TemplateResponse("home.html", {"request": request, "user": user})

# Login Ekranı
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

# Signup Ekranı
@app.get("/signup", response_class=HTMLResponse)
async def signup_page(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request})

# Yayın Ekranı
@app.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, user: Optional[User] = Depends(get_current_user)):
    return templates.TemplateResponse("live.html", {"request": request, "user": user})

# API: Kayıt Ol
@app.post("/auth/signup")
async def signup(
    request: Request, 
    email: str = Form(...), 
    password: str = Form(...), 
    password_confirm: str = Form(...),
    db: Session = Depends(get_db)
):
    # 1. Şifre Kontrolü
    if password != password_confirm:
        return templates.TemplateResponse("signup.html", {"request": request, "error": "Şifreler uyuşmuyor."})

    # 2. Email Kullanımda mı?
    if db.query(User).filter(User.email == email).first():
        return templates.TemplateResponse("signup.html", {"request": request, "error": "Bu e-posta adresi zaten kayıtlı."})
    
    # 3. Kayıt (Username YOK)
    hashed_password = get_password_hash(password)
    verification_code = str(random.randint(100000, 999999))
    
    new_user = User(
        email=email,
        username=None, # Başlangıçta boş
        password_hash=hashed_password,
        verification_code=verification_code,
        is_verified=False
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # 4. Mail Gönder (Brevo)
    # send_brevo_email(email, verification_code) # (Fonksiyonun kodda tanımlı olduğunu varsayıyorum)
    print(f"DEBUG: Doğrulama Kodu: {verification_code}") # Test için konsola da yazalım
    
    return RedirectResponse(url=f"/verify?email={email}", status_code=303)

# API: Giriş Yap
@app.post("/auth/login")
async def login(
    request: Request, 
    email: str = Form(...), # Username yerine Email alıyoruz
    password: str = Form(...), 
    db: Session = Depends(get_db)
):
    # Email'e göre kullanıcıyı bul
    user = db.query(User).filter(User.email == email).first()
    
    if not user:
        return templates.TemplateResponse("login.html", {"request": request, "error": "Bu e-posta ile kayıtlı kullanıcı yok."})
    
    if not verify_password(password, user.password_hash):
        return templates.TemplateResponse("login.html", {"request": request, "error": "Şifre hatalı."})
    
    if not user.is_verified:
         return templates.TemplateResponse("login.html", {"request": request, "error": "Lütfen önce e-postanızı doğrulayın."})
    
    # Token oluştur (Identity olarak email kullanıyoruz artık)
    access_token = create_access_token(data={"sub": user.email})
    
    response = RedirectResponse(url="/", status_code=303)
    response.set_cookie(key="access_token", value=f"Bearer {access_token}", httponly=True)
    return response

# API: Çıkış Yap
@app.get("/logout")
async def logout():
    response = RedirectResponse(url="/", status_code=303)
    response.delete_cookie("access_token")
    return response

# ==========================================
# 5. WEBSOCKET & FFMPEG (YAYIN MOTORU)
# ==========================================
stream_process = None

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

manager = ConnectionManager()

@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket):
    global stream_process
    await websocket.accept()
    print("Yayıncı bağlandı. Motor Başlatılıyor...")

    command = [
        "ffmpeg",
        "-f", "webm",
        "-i", "pipe:0",
        
        # --- GÖRÜNTÜ AYARLARI (Stabil & Net) ---
        "-vf", "scale=720:1280,fps=30",
        "-c:v", "libx264",
        "-preset", "superfast",
        "-tune", "zerolatency",
        "-b:v", "1200k",              # 1.2 Mbps (Altın Oran)
        "-maxrate", "1500k",
        "-bufsize", "3000k",
        "-g", "30",

        # --- SES AYARLARI (Yüksek Kalite) ---
        "-c:a", "aac",
        "-ar", "48000",               # 48 KHz
        "-ac", "2",                   # Stereo
        "-b:a", "192k",               # 192 Kbps
        "-af", "aresample=async=1",   

        # --- HLS AYARLARI ---
        "-f", "hls",
        "-hls_time", "1",
        "-hls_list_size", "4",
        "-hls_flags", "delete_segments",
        "-hls_allow_cache", "0",
        "static/hls/stream.m3u8"
    ]

    stream_process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        while True:
            data = await websocket.receive_bytes()
            if stream_process and stream_process.stdin:
                stream_process.stdin.write(data)
                stream_process.stdin.flush()
    except WebSocketDisconnect:
        print("Yayıncı ayrıldı.")
        if stream_process:
            stream_process.terminate()
            stream_process = None
            os.system("rm -rf static/hls/*")
    except Exception as e:
        print(f"Hata: {e}")
        if stream_process:
            stream_process.terminate()

@app.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            clean = data.replace("<", "&lt;")
            await manager.broadcast(clean)
    except:
        manager.disconnect(websocket)