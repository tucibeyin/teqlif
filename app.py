import os
import subprocess
import signal
from fastapi import FastAPI, WebSocket, Request, BackgroundTasks, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# 1. Statik Dosyalar (Video parçaları burada olacak)
# Not: VPS'te burayı RAM'e bağlayacağız.
os.makedirs("static/hls", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Aktif yayın sürecini ve sohbet bağlantılarını tutan hafıza
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
        # Bağlı herkese mesajı gönder
        for connection in self.active_connections:
            await connection.send_text(message)

manager = ConnectionManager()

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    # Ana sayfayı göster
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/start_stream")
async def start_stream():
    global stream_process
    
    # Zaten yayın varsa tekrar başlatma
    if stream_process is not None and stream_process.poll() is None:
        return {"status": "Yayın zaten aktif"}

    # FFmpeg Komutu (KAYITSIZ CANLI YAYIN MOTORU)
    # Bu komut yapay bir test yayını üretir. 
    # Gerçek hayatta "-i testsrc" yerine RTMP girişi konur.
    command = [
        "ffmpeg",
        "-re",
        "-f", "lavfi", "-i", "testsrc=size=1080x1920:rate=30", # Dikey Görüntü (Simülasyon)
        "-f", "lavfi", "-i", "sine=frequency=440", # Ses (Simülasyon)
        "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
        "-c:a", "aac", "-ar", "44100",
        "-f", "hls",
        "-hls_time", "2",           # 2 saniyelik parçalar (Düşük gecikme için)
        "-hls_list_size", "4",      # Listede SADECE son 4 parça tutulur (Eskiler silinir!)
        "-hls_flags", "delete_segments", # Diskteki eski dosyaları fiziksel olarak sil
        "static/hls/stream.m3u8"
    ]

    # İşlemi başlat
    stream_process = subprocess.Popen(command)
    return {"status": "Yayın Başladı", "url": "/static/hls/stream.m3u8"}

@app.post("/stop_stream")
async def stop_stream():
    global stream_process
    if stream_process:
        stream_process.terminate()
        stream_process = None
        # Temizlik: Kalan parçaları sil
        os.system("rm -rf static/hls/*")
        return {"status": "Yayın Durduruldu ve Temizlendi"}
    return {"status": "Aktif yayın yok"}

@app.websocket("/ws/chat")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # Basit bir XSS koruması (HTML taglerini engelle)
            clean_data = data.replace("<", "&lt;").replace(">", "&gt;")
            await manager.broadcast(clean_data)
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# Çalıştırma komutu (VPS'te):
# uvicorn app:app --host 0.0.0.0 --port 5000