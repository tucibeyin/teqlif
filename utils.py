import os
import requests
from datetime import datetime, timedelta
from passlib.context import CryptContext
from jose import JWTError, jwt
from fastapi import Request, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import User

# Ayarlar
SECRET_KEY = os.getenv("SECRET_KEY", "gizli_anahtar_degistir")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

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

# Mail Fonksiyonları
def send_brevo_email(to_email: str, subject: str, html_content: str):
    try:
        api_key = os.getenv("BREVO_API_KEY")
        if not api_key:
            print(f"📧 [MOCK MAIL] Kime: {to_email} | Konu: {subject}")
            return
        url = "https://api.brevo.com/v3/smtp/email"
        headers = {"accept": "application/json", "api-key": api_key, "content-type": "application/json"}
        data = {"sender": {"name": "Teqlif", "email": os.getenv("SENDER_EMAIL")}, "to": [{"email": to_email}], "subject": subject, "htmlContent": html_content}
        requests.post(url, json=data, headers=headers)
    except Exception as e: print(f"Mail hatası: {e}")

def send_welcome_email(to_email: str):
    send_brevo_email(to_email, "Hoş Geldiniz!", "<p>Hesabınız başarıyla doğrulandı.</p>")

def send_broadcast_notifications_task(follower_emails: list, username: str):
    if not follower_emails: return
    html = f"<h1>{username} YAYINDA! 🔴</h1><a href='https://teqlif.com/live?mode=watch&broadcaster={username}'>İzlemek için tıkla</a>"
    for email in follower_emails:
        send_brevo_email(email, f"🔴 {username} Yayında!", html)