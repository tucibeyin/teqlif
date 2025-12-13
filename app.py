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
    print("Yayıncı bağlandı. KESİNTİSİZ MOD (CBR + Forced Keyframe)...")

    command = [
        "ffmpeg",
        "-f", "webm",
        "-i", "pipe:0",
        
        # --- GÖRÜNTÜ İŞLEME ---
        "-vf", "scale=720:1280,fps=30", # Boyut ve FPS sabitleme
        "-c:v", "libx264",
        "-preset", "superfast",       # İşlemciyi yormadan hızlı çevir
        "-tune", "zerolatency",
        
        # --- CERRAHİ KESİM (STUTTER FIX) ---
        "-force_key_frames", "expr:gte(t,n_forced*1)", # HER 1 SANİYEDE ZORLA KEYFRAME AT
        "-sc_threshold", "0",         # Sahne değişimini bekleme, robot gibi kes
        
        # --- SABİT BITRATE (CBR) ---
        "-b:v", "2000k",              # Hedef Hız
        "-minrate", "2000k",          # Minimum Hız (Düşme!)
        "-maxrate", "2000k",          # Maksimum Hız (Çıkma!)
        "-bufsize", "4000k",          # Tampon

        # --- SES ---
        "-c:a", "aac",
        "-ar", "44100",
        "-af", "aresample=async=1",   # Ses senkronu

        # --- HLS ÇIKTI ---
        "-f", "hls",
        "-hls_time", "1",             # Tam 1 saniyelik parçalar
        "-hls_list_size", "4",        # 4 parça tut (Güvenli akış)
        "-hls_flags", "delete_segments+split_by_time", # Süreye göre kesin böl
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