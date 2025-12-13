import os
import subprocess
import asyncio
from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# RAM Disk Kontrolü
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
        "-f", "webm",
        "-i", "pipe:0",
        
        # --- GÖRÜNTÜ AYARLARI ---
        "-vf", "scale=720:1280",      # Zorla 720p Dikey
        "-c:v", "libx264",
        "-preset", "ultrafast",       # En hızlı mod
        "-tune", "zerolatency",       # Gecikme yok
        "-r", "30",                   # 30 FPS Sabit
        "-g", "30",                   # Her 1 saniyede bir anahtar kare
        "-b:v", "2000k",              # 2000k Bitrate
        "-bufsize", "2000k",          # Tamponu küçük tut ki beklemesin

        # --- SES AYARLARI ---
        "-c:a", "aac",
        "-ar", "44100",
        "-af", "aresample=async=1",   # Ses kaymasını önle

        # --- HLS LOW LATENCY AYARLARI ---
        "-f", "hls",
        "-hls_time", "1",             # 1 saniyelik parçalar
        "-hls_list_size", "2",        # Listede sadece SON 2 parça kalsın (Eskisi 3-4 tü)
        "-hls_flags", "delete_segments",
        "-hls_allow_cache", "0",      # Asla önbellekleme
        "static/hls/stream.m3u8"
    ]

    # stderr=subprocess.DEVNULL ile log kirliliğini engelliyoruz
    stream_process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

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