import os
import subprocess
import asyncio
from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# Temizlik ve Klasör Yapısı
os.system("rm -rf static/hls/*")
os.makedirs("static/hls", exist_ok=True)

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

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

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.websocket("/ws/broadcast")
async def broadcast_endpoint(websocket: WebSocket):
    global stream_process
    await websocket.accept()
    print("Yayıncı bağlandı. ABR Modu (720p + 360p) Başlatılıyor...")

    command = [
        "ffmpeg",
        "-f", "webm",
        "-i", "pipe:0",
        
        # --- FILTRE KOMPLEKSI (Görüntüyü İkiye Böl) ---
        # [v1]: 720p (Yüksek Kalite)
        # [v2]: 360p (Düşük Kalite - Donmaması için)
        "-filter_complex", 
        "[0:v]split=2[v1][v2]; [v1]scale=720:1280,fps=30[v720]; [v2]scale=360:640,fps=30[v360]",
        
        # --- ORTAK HIZ AYARLARI ---
        "-preset", "ultrafast",
        "-tune", "zerolatency",
        "-sc_threshold", "0",
        
        # --- AKIŞ 1: 720p (Yüksek) ---
        "-map", "[v720]", "-c:v:0", "libx264", "-b:v:0", "1500k", "-maxrate:v:0", "1800k", "-bufsize:v:0", "3000k", "-g:v:0", "30",
        
        # --- AKIŞ 2: 360p (Düşük) ---
        "-map", "[v360]", "-c:v:1", "libx264", "-b:v:1", "600k",  "-maxrate:v:1", "800k",  "-bufsize:v:1", "1200k", "-g:v:1", "30",
        
        # --- SES (Tek kaynak) ---
        "-map", "0:a", "-c:a", "aac", "-ar", "44100", "-b:a", "64k", "-ac", "1",
        
        # --- HLS ÇIKTI AYARLARI (MASTER PLAYLIST) ---
        "-f", "hls",
        "-hls_time", "1",             # 1 saniyelik parçalar (Düşük Latency)
        "-hls_list_size", "4",        # Son 4 parça
        "-hls_flags", "delete_segments+independent_segments",
        "-master_pl_name", "master.m3u8", # Ana yönetici dosya
        
        # Hangi akışın hangi ayarları kullanacağı
        "-var_stream_map", "v:0,a:0,name:720p v:1,a:0,name:360p", 
        
        "static/hls/stream_%v.m3u8"
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