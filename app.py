import os
import subprocess
import asyncio
from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# RAM Disk Ayarı (Dosyalar RAM'de)
os.makedirs("static/hls", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Aktif yayın sürecini tutan değişken
stream_process = None

# Chat Yöneticisi
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

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

# YAYINCI: Görüntüyü Buraya Gönderir (WebSocket)
@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket):
    global stream_process
    await websocket.accept()
    
    print("Yayıncı bağlandı, FFmpeg başlatılıyor...")

    # FFmpeg Komutu: Girdiyi "pipe:0" (Python'dan) al
    command = [
        "ffmpeg",
        # --- GİRİŞ AYARLARI (KRİTİK DÜZELTME) ---
        "-f", "webm",                 # Gelen verinin formatı WebM
        "-use_wallclock_as_timestamps", "1", # Tarayıcı zamanına güvenme, sunucu saatini kullan
        "-fflags", "+genpts",         # Zaman çizelgesini yeniden oluştur
        "-i", "pipe:0",               # Girdi: WebSocket
        
        # --- ÇIKIŞ AYARLARI ---
        "-c:v", "libx264",
        "-preset", "superfast",
        "-tune", "zerolatency",
        
        "-b:v", "2000k",              # Bitrate (İnterneti yormamak için 2000k yeterli)
        "-maxrate", "2500k",
        "-bufsize", "5000k",
        "-g", "60",                   # 2 saniyede bir keyframe
        "-r", "30",                   # Çıktıyı zorla 30 FPS yap (Dalgalanmayı önler)
        
        "-c:a", "aac",
        "-ar", "44100",
        "-f", "hls",
        "-hls_time", "2",             
        "-hls_list_size", "6", 
        "-hls_flags", "delete_segments",
        "static/hls/stream.m3u8"
    ]

    # FFmpeg işlemini başlat ve girdiyi (stdin) aç
    stream_process = subprocess.Popen(command, stdin=subprocess.PIPE)

    try:
        while True:
            # Tarayıcıdan gelen video verisini (blob) al
            data = await websocket.receive_bytes()
            
            # Veriyi FFmpeg'e yaz
            if stream_process and stream_process.stdin:
                stream_process.stdin.write(data)
                
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

# İZLEYİCİ: Chat
@app.websocket("/ws/chat")
async def chat_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            clean_data = data.replace("<", "&lt;").replace(">", "&gt;")
            await manager.broadcast(clean_data)
    except WebSocketDisconnect:
        manager.disconnect(websocket)