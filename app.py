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
    print("Yayıncı bağlandı. Görüntü + Ses Modu...")

    command = [
        "ffmpeg",
        "-f", "webm",
        "-i", "pipe:0",
        
        # --- GÖRÜNTÜ (Dokunmuyoruz, gayet iyi) ---
        "-vf", "scale=720:1280",      
        "-c:v", "libx264",
        "-preset", "superfast",       
        "-tune", "zerolatency",
        
        "-r", "30",                   
        "-g", "30",                   
        "-b:v", "1500k",              
        "-maxrate", "2000k",
        "-bufsize", "4000k",

        # --- SES AYARLARI (KRİTİK GÜNCELLEME) ---
        "-c:a", "aac",                # HLS için standart ses formatı
        "-ar", "44100",               # 44.1 KHz (Standart)
        "-ac", "2",                   # Stereo Ses (Daha dolgun)
        "-b:a", "128k",               # 128 Kbps (Net ses)
        "-af", "aresample=async=1",   # Görüntüyle sesi zorla eşle (Sync Fix)

        # --- HLS AYARLARI ---
        "-f", "hls",
        "-hls_time", "1",             
        "-hls_list_size", "4",        
        "-hls_flags", "delete_segments",
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