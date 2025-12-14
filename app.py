import os
import subprocess
import asyncio
import json
import random # Kod üretmek için
import requests # Brevo maili için
from datetime import datetime, timedelta
from typing import Optional, List

# --- .ENV YÜKLEME ---
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect, Depends, Form, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.security import OAuth2PasswordBearer

# --- VERİTABANI & GÜVENLİK ---
# DÜZELTME BURADA YAPILDI: "Boolean" eklendi
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from passlib.context import CryptContext
from jose import JWTError, jwt

app = FastAPI()

# ==========================================
# 1. AYARLAR (CONFIG)
# ==========================================

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
if not SQLALCHEMY_DATABASE_URL:
    raise ValueError("HATA: .env dosyasında DATABASE_URL bulunamadı!")

SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise ValueError("HATA: .env dosyasında SECRET_KEY bulunamadı!")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 

# Klasör Temizliği
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
    username = Column(String, unique=True, index=True, nullable=True) # Boş olabilir
    password_hash = Column(String)
    verification_code = Column(String)
    is_verified = Column(Boolean, default=False) # Boolean hatası düzeldi
    created_at = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ==========================================
# 3. GÜVENLİK VE YARDIMCI FONKSİYONLAR
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
        email: str = payload.get("sub") # Token'dan email okuyoruz
        if email is None: return None
    except JWTError:
        return None
    
    user = db.query(User).filter(User.email == email).first()
    return user

# --- BREVO MAIL GÖNDERME ---
def send_brevo_email(to_email, code):
    api_key = os.getenv("BREVO_API_KEY")
    sender_email = os.getenv("SENDER_EMAIL", "no-reply@teqlif.com")
    url = "https://api.brevo.com/v3/smtp/email"
    
    headers = {
        "accept": "application/json",
        "api-key": api_key,
        "content-type": "application/json"
    }
    
    data = {
        "sender": {"name": "Teqlif Live", "email": sender_email},
        "to": [{"email": to_email}],
        "subject": "Teqlif Hesap Doğrulama Kodu",
        "htmlContent": f"""
            <div style="font-family: sans-serif; text-align: center; padding: 20px;">
                <h1>Hoş Geldiniz!</h1>
                <p>Teqlif hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>
                <h2 style="background: #eee; padding: 10px; display: inline-block; letter-spacing: 5px; color: #333;">{code}</h2>
                <p style="color: #888; font-size: 12px; margin-top: 20px;">Bu kodu siz istemediyseniz bu maili dikkate almayın.</p>
            </div>
        """
    }
    
    try:
        response = requests.post(url, json=data, headers=headers)
        print("Email Durumu:", response.status_code)
    except Exception as e:
        print("Email Hatası:", e)

# --- HOŞ GELDİN MAİLİ GÖNDERME ---
def send_welcome_email(to_email):
    api_key = os.getenv("BREVO_API_KEY")
    sender_email = os.getenv("SENDER_EMAIL", "no-reply@teqlif.com")
    url = "https://api.brevo.com/v3/smtp/email"
    
    headers = {
        "accept": "application/json",
        "api-key": api_key,
        "content-type": "application/json"
    }
    
    data = {
        "sender": {"name": "Teqlif Live", "email": sender_email},
        "to": [{"email": to_email}],
        "subject": "Hoş Geldiniz! Hesabınız Onaylandı ✅",
        "htmlContent": f"""
            <div style="font-family: sans-serif; text-align: center; padding: 20px; color: #333;">
                <h1 style="color: #27ae60;">Tebrikler! 🎉</h1>
                <p>Hesabınız başarıyla doğrulandı.</p>
                <p>Artık Teqlif Live dünyasına giriş yapabilir, yayın açabilir ve sohbete katılabilirsiniz.</p>
                <br>
                <a href="https://teqlif.com/login" style="background: #e74c3c; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">Giriş Yap</a>
            </div>
        """
    }
    
    try:
        requests.post(url, json=data, headers=headers)
    except Exception as e:
        print("Welcome Email Hatası:", e)

# ==========================================
# 4. ROTALAR (ROUTES)
# ==========================================

@app.get("/", response_class=HTMLResponse)
async def read_home(request: Request, user: Optional[User] = Depends(get_current_user)):
    return templates.TemplateResponse("home.html", {"request": request, "user": user})

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.get("/signup", response_class=HTMLResponse)
async def signup_page(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request})

# --- YAYIN VE İZLEME EKRANI (GÜVENLİKLİ) ---
@app.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, user: Optional[User] = Depends(get_current_user)):
    # GÜVENLİK KONTROLÜ: Kullanıcı giriş yapmamışsa Login'e postala
    if not user:
        return RedirectResponse(url="/login?error=Lütfen önce giriş yapın", status_code=303)
        
    return templates.TemplateResponse("live.html", {"request": request, "user": user})

# --- KAYIT OL (EMAIL + ŞİFRE) ---
@app.post("/auth/signup")
async def signup(
    request: Request, 
    email: str = Form(...), 
    password: str = Form(...), 
    password_confirm: str = Form(...),
    db: Session = Depends(get_db)
):
    if password != password_confirm:
        return templates.TemplateResponse("signup.html", {"request": request, "error": "Şifreler uyuşmuyor."})

    if db.query(User).filter(User.email == email).first():
        return templates.TemplateResponse("signup.html", {"request": request, "error": "Bu e-posta adresi zaten kayıtlı."})
    
    hashed_password = get_password_hash(password)
    verification_code = str(random.randint(100000, 999999))
    
    new_user = User(
        email=email,
        username=None,
        password_hash=hashed_password,
        verification_code=verification_code,
        is_verified=False
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # Mail Gönder
    send_brevo_email(email, verification_code)
    print(f"DEBUG KOD: {verification_code}") # Mail gitmezse konsoldan görmek için
    
    return RedirectResponse(url=f"/verify?email={email}", status_code=303)

# --- DOĞRULAMA SAYFASI ---
@app.get("/verify", response_class=HTMLResponse)
async def verify_page(request: Request, email: str):
    return templates.TemplateResponse("verify.html", {"request": request, "email": email})

# --- DOĞRULAMA İŞLEMİ ---
# --- DOĞRULAMA İŞLEMİ ---
@app.post("/auth/verify")
async def verify_code(
    request: Request, 
    email: str = Form(...), 
    code: str = Form(...), 
    db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == email).first()
    
    if not user:
        return templates.TemplateResponse("verify.html", {"request": request, "email": email, "error": "Kullanıcı bulunamadı."})
    
    if user.verification_code != code:
        return templates.TemplateResponse("verify.html", {"request": request, "email": email, "error": "Hatalı kod, lütfen tekrar deneyin."})
    
    # Başarılı Doğrulama
    user.is_verified = True
    user.verification_code = None
    db.commit()
    
    # 1. Hoş Geldin Maili Gönder
    send_welcome_email(email)
    
    # 2. Login Ekranına "Başarılı" mesajıyla gönder
    return RedirectResponse(url="/login?msg=verified", status_code=303)

# --- GİRİŞ YAP (EMAIL İLE) ---
@app.post("/auth/login")
async def login(
    request: Request, 
    email: str = Form(...), 
    password: str = Form(...), 
    db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == email).first()
    
    if not user:
        return templates.TemplateResponse("login.html", {"request": request, "error": "Bu e-posta ile kayıtlı kullanıcı yok."})
    
    if not verify_password(password, user.password_hash):
        return templates.TemplateResponse("login.html", {"request": request, "error": "Şifre hatalı."})
    
    if not user.is_verified:
         # Doğrulanmamışsa tekrar doğrulama sayfasına yönlendirilebilir veya uyarı verilir
         return templates.TemplateResponse("login.html", {"request": request, "error": "Lütfen önce e-postanızı doğrulayın."})
    
    access_token = create_access_token(data={"sub": user.email})
    
    response = RedirectResponse(url="/", status_code=303)
    response.set_cookie(key="access_token", value=f"Bearer {access_token}", httponly=True)
    return response

@app.get("/logout")
async def logout():
    response = RedirectResponse(url="/", status_code=303)
    response.delete_cookie("access_token")
    return response

# ==========================================
# 5. WEBSOCKET & YAYIN MOTORU
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


# ==========================================
# 6. AYARLAR VE PROFİL (YENİ)
# ==========================================

# --- AYARLAR SAYFASI (GÖRÜNTÜLE) ---
@app.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, user: Optional[User] = Depends(get_current_user)):
    if not user:
        return RedirectResponse(url="/login", status_code=303)
    return templates.TemplateResponse("settings.html", {"request": request, "user": user})

# --- PROFİL GÜNCELLEME (İŞLEM) ---
@app.post("/settings/update")
async def update_profile(
    request: Request,
    username: str = Form(...),
    user: User = Depends(get_current_user), # Giriş yapmış kullanıcı şart
    db: Session = Depends(get_db)
):
    if not user:
        return RedirectResponse(url="/login", status_code=303)

    # 1. Kullanıcı adı değişmiş mi kontrol et
    # Eğer aynı ismi gönderdiyse işlem yapmaya gerek yok ama hata da verme
    if username == user.username:
        return templates.TemplateResponse("settings.html", {
            "request": request, "user": user, "success": "Bilgiler güncel."
        })

    # 2. AYNI İSİM BAŞKASINDA VAR MI? (Kritik Nokta)
    # Veritabanında bu username'e sahip, ama ID'si benim ID'm olmayan biri var mı?
    existing_user = db.query(User).filter(User.username == username).first()
    
    if existing_user:
        return templates.TemplateResponse("settings.html", {
            "request": request, 
            "user": user, 
            "error": f"Üzgünüz, '{username}' kullanıcı adı başkası tarafından alınmış."
        })

    # 3. Güncelleme İşlemi
    try:
        user.username = username
        db.commit()
        db.refresh(user)
        return templates.TemplateResponse("settings.html", {
            "request": request, 
            "user": user, 
            "success": "Profiliniz başarıyla güncellendi! 🎉"
        })
    except Exception as e:
        return templates.TemplateResponse("settings.html", {
            "request": request, "user": user, "error": "Bir hata oluştu."
        })

manager = ConnectionManager()

@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket):
    global stream_process
    await websocket.accept()
    print("Yayıncı bağlandı...")

# GÜVENLİ VE KARARLI FFMPEG KOMUTU
# HD YAYIN İÇİN FFMPEG KOMUTU
    command = [
        "ffmpeg", 
        "-i", "pipe:0",               # Girdi (Artık HD geliyor)
        
        "-c:v", "libx264",            # Video Codec
        "-preset", "superfast",       # İşlemciyi yormadan hızlı çevir (Kalite/Hız dengesi)
        "-tune", "zerolatency",       # Düşük gecikme
        
        # --- KALİTE AYARLARI ---
        "-b:v", "2500k",              # Hedef Bitrate: 2500k (720p için ideal)
        "-maxrate", "3000k",          # Maksimum anlık bitrate
        "-bufsize", "6000k",          # Tampon boyutu
        "-vf", "scale=1280:-2",       # Çözünürlüğü 1280x720'ye sabitle (Gelen ne olursa olsun)
        "-g", "60",                   # GOP (2 saniye)
        
        "-c:a", "aac",                # Ses Codec
        "-b:a", "128k",               # Ses Kalitesi
        "-ar", "44100",
        
        "-f", "hls",
        "-hls_time", "2",
        "-hls_list_size", "5",
        "-hls_flags", "delete_segments", 
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
        if stream_process: stream_process.terminate(); stream_process = None; os.system("rm -rf static/hls/*")
    except Exception:
        if stream_process: stream_process.terminate()

# --- YENİ AKILLI CHAT MOTORU ---
@app.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await manager.connect(websocket)
    
    # 1. KULLANICIYI TANI (KİMLİK KONTROLÜ)
    username = "Misafir" # Varsayılan
    try:
        token = websocket.cookies.get("access_token")
        if token:
            scheme, _, param = token.partition(" ")
            payload = jwt.decode(param, SECRET_KEY, algorithms=[ALGORITHM])
            email = payload.get("sub")
            
            # Veritabanından en güncel ismini çek
            user = db.query(User).filter(User.email == email).first()
            if user:
                # Kullanıcı adı varsa onu al, yoksa emailin başını al
                username = user.username if user.username else user.email.split("@")[0]
    except:
        pass # Hata olursa Misafir kalır
    
    try:
        while True:
            # Mesajı al
            data = await websocket.receive_text()
            
            # XSS Güvenliği (HTML etiketlerini temizle)
            clean_msg = data.replace("<", "&lt;").replace(">", "&gt;")
            
            # Mesaj boşsa gönderme
            if not clean_msg.strip():
                continue

            # 2. MESAJI PAKETLE (JSON)
            # Sadece metni değil, kimin gönderdiğini de paketliyoruz
            message_package = json.dumps({
                "user": username,
                "msg": clean_msg
            })
            
            # Herkese gönder
            await manager.broadcast(message_package)
            
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"Chat Hatası: {e}")
        manager.disconnect(websocket)