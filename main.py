import os
import shutil
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from database import engine, Base
from routers import auth, general, stream

# Veritabanı Tablolarını Oluştur (Otomatik)
Base.metadata.create_all(bind=engine)

# Uygulama Başlat
app = FastAPI(title="Teqlif Live")

# Statik Dosya Hazırlığı
os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/thumbnails", exist_ok=True)

# Başlangıçta eski yayın dosyalarını temizle
if os.path.exists("static/hls"):
    shutil.rmtree("static/hls", ignore_errors=True)
    os.makedirs("static/hls", exist_ok=True)

app.mount("/static", StaticFiles(directory="static"), name="static")

# Rotaları (Router) Dahil Et - BURASI ÇOK ÖNEMLİ
app.include_router(auth.router)
app.include_router(general.router)
app.include_router(stream.router)