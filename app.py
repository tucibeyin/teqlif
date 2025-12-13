import os
import subprocess
import asyncio
from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# RAM Disk Ayarı
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
    print("Yayıncı bağlandı. FFmpeg başlatılıyor...")

    command = [
        "ffmpeg",
        "-f", "webm",                 # Girdi Formatı
        "-i", "pipe:0",               # WebSocket'ten oku
        
        # --- VİDEO İŞLEME (Sabitleme) ---
        "-vf", "scale=720:1280",      # Zorla 720p Dikey yap (Kırpılmayı önler)
        "-c:v", "libx264",
        "-preset", "ultrafast",       # Hız için ultrafast
        "-tune", "zerolatency",
        "-r", "30",                   # Çıktıyı 30 FPS'e sabitle
        "-g", "60",                   # 2 saniyede bir keyframe
        "-b:v", "2000k",              # Bitrate sınırı
        "-bufsize", "4000k",

        # --- SES SENKRONİZASYONU (Donmayı önler) ---
        "-c:a", "aac",
        "-ar", "44100",
        "-af", "aresample=async=1",   # Ses kaymasını otomatik düzelt (Kritik!)

        # --- HLS ÇIKTI ---
        "-f", "hls",
        "-hls_time", "1",             # 1 Saniyelik parçalar (Hız için)
        "-hls_list_size", "4", 
        "-hls_flags", "delete_segments",
        "static/hls/stream.m3u8"
    ]

    stream_process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL) 
    # stderr=DEVNULL yaptık ki loglar terminali kilitlemesin

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