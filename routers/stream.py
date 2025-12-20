import os
import asyncio
from fastapi import APIRouter, WebSocket, Request, Depends, Form
from fastapi.responses import StreamingResponse, HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from models import User
from utils import get_current_user, SECRET_KEY, ALGORITHM

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# --- İSTEMCİ LOGLARI ---
@router.post("/log/client")
async def client_log(request: Request):
    try:
        data = await request.json()
        print(f"📱 [CLIENT] {data.get('msg')}")
        return {"status": "ok"}
    except: return {"status": "err"}

# --- SAYFA ROTALARI ---
@router.get("/live", response_class=HTMLResponse)
async def read_live(request: Request, mode: str = "watch", broadcaster: str = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse("/login", 303)
    target_user = None
    if broadcaster: target_user = db.query(User).filter(User.username == broadcaster).first()
    return templates.TemplateResponse("live.html", {"request": request, "user": user, "mode": mode, "broadcaster": target_user})

@router.post("/broadcast/start")
async def start(title: str = Form(...), category: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.is_live = True; user.stream_title = title; user.stream_category = category; db.commit()
    return {"status": "ok"}

@router.post("/broadcast/stop")
async def stop(user: User = Depends(get_current_user)):
    # Temizlik
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == user.username).first()
        if u: u.is_live = False; db.commit()
    finally: db.close()
    return {"status": "stopped"}

@router.post("/broadcast/thumbnail")
async def thumb(request: Request): return {"status": "ok"} # Basit geç

# --- 1. YAYINCI SOCKETİ (KAYDEDİCİ) ---
@router.websocket("/ws/broadcast")
async def broadcast(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    
    # Kullanıcıyı bul
    try:
        token = websocket.cookies.get("access_token")
        from jose import jwt
        payload = jwt.decode(token.partition(" ")[2], SECRET_KEY, algorithms=[ALGORITHM])
        user = db.query(User).filter(User.email == payload.get("sub")).first()
        username = user.username
    except:
        print("❌ Yetkisiz Giriş Denemesi")
        await websocket.close()
        return

    # Klasör Hazırla
    stream_dir = f"static/hls/{username}"
    if not os.path.exists(stream_dir): os.makedirs(stream_dir, exist_ok=True)
    
    # Dosyayı "wb" (Write Binary) modunda aç
    file_path = f"{stream_dir}/stream.webm"
    print(f"🎥 YAYIN BAŞLIYOR: {username} -> {file_path}")
    
    try:
        with open(file_path, "wb") as f:
            while True:
                # Veri bekle
                data = await websocket.receive_bytes()
                
                # Yaz ve Kaydet
                f.write(data)
                f.flush()
                os.fsync(f.fileno()) # Diske kazı (Gecikmeyi önler)
                
                # Log (Opsiyonel: Çok log yaparsa kapatabilirsin)
                # print(f"📥 {len(data)} bayt yazıldı.")
                
    except Exception as e:
        print(f"⚠️ Yayın Kesildi ({username}): {e}")
    finally:
        # Yayını veritabanından düşür
        cleanup_db(username)

def cleanup_db(username):
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == username).first()
        if u: u.is_live = False; db.commit()
        print(f"🛑 Yayın kapandı: {username}")
    finally: db.close()

# --- 2. İZLEYİCİ SOCKETİ (STREAMER) ---
def file_iterator(file_path):
    """Dosyayı sürekli okuyan fonksiyon"""
    # Dosya oluşana kadar bekle
    tries = 0
    while not os.path.exists(file_path):
        time.sleep(0.5)
        tries += 1
        if tries > 10: return # 5 sn içinde yayın gelmezse pes et

    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(1024 * 64) # 64KB oku
            if not chunk:
                time.sleep(0.1) # Veri bittiyse bekle (Canlı yayın sürüyor)
                continue
            yield chunk

@router.get("/stream/{username}")
async def stream_endpoint(username: str):
    file_path = f"static/hls/{username}/stream.webm"
    # StreamingResponse: Dosyayı indirtmez, parça parça oynatır
    return StreamingResponse(file_iterator(file_path), media_type="video/webm")

# --- CHAT (STANDART) ---
@router.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True: await websocket.receive_text() # Chat şimdilik boş
    except: pass