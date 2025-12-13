import os
import subprocess
import asyncio
from fastapi import FastAPI, WebSocket, Request, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import List

app = FastAPI()

# Temizlik
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
    print("Yayıncı bağlandı. Akıcı Mod Aktif...")

    command = [
        "ffmpeg",
        # --- GİRİŞ ZAMANLAMA DÜZELTMELERİ (Stutter Fix) ---
        "-f", "webm",
        "-fflags", "+genpts",                  # Eksik zaman damgalarını üret
        "-use_wallclock_as_timestamps", "1",   # Sunucu saatini baz al (Kesilmeyi önler)
        "-i", "pipe:0",
        
        # --- VİDEO İŞLEME ---
        "-vf", "scale=720:1280",      
        "-c:v", "libx264",
        "-preset", "superfast",       # Ultrafast bazen kare atlar, Superfast daha akıcıdır
        "-tune", "zerolatency",
        "-r", "30",                   # Çıktıyı 30 FPS'e zorla
        "-g", "30",                   # Her 1 saniyede bir Keyframe
        "-b:v", "1500k",              # 1.5 Mbps (Mobil için ideal akıcılık)
        "-bufsize", "3000k",          

        "-c:a", "aac",
        "-ar", "44100",
        "-af", "aresample=async=1",   # Ses senkronizasyonu

        # --- HLS AYARLARI ---
        "-f", "hls",
        "-hls_time", "1",             # 1 saniyelik parçalar
        "-hls_list_size", "4",        # Oynatıcıya biraz pay bırak (Akıcılık için)
        "-hls_flags", "delete_segments",
        "-hls_allow_cache", "0",
        "static/hls/stream.m3u8"
    ]

    # Hataları görmek için stderr=PIPE
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