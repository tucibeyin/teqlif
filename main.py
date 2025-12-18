import os
import shutil
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from database import engine, Base, SessionLocal
from routers import auth, general, stream
from models import User

# Veritabanı tablolarını oluştur
Base.metadata.create_all(bind=engine)

app = FastAPI()

# Statik dosyalar
app.mount("/static", StaticFiles(directory="static"), name="static")

# Routerları dahil et
app.include_router(auth.router)
app.include_router(general.router)
app.include_router(stream.router)

# 🔥 BAŞLANGIÇ TEMİZLİĞİ (ZOMBİ YAYINLARI SİLME) 🔥
@app.on_event("startup")
def startup_event():
    print("🧹 SİSTEM BAŞLATILIYOR: Zombi yayınlar temizleniyor...")
    
    # 1. Veritabanındaki herkesi 'Offline' yap
    db = SessionLocal()
    try:
        count = db.query(User).filter(User.is_live == True).update({User.is_live: False})
        db.commit()
        print(f"✅ {count} adet zombi yayın veritabanından düşürüldü.")
    except Exception as e:
        print(f"❌ DB Temizlik Hatası: {e}")
    finally:
        db.close()

    # 2. Eski HLS dosyalarını fiziksel olarak sil
    hls_dir = "static/hls"
    if os.path.exists(hls_dir):
        shutil.rmtree(hls_dir)  # Klasörü tamamen sil
        os.makedirs(hls_dir)    # Boş olarak tekrar oluştur
        print("✅ HLS önbellek dosyaları temizlendi.")
    else:
        os.makedirs(hls_dir)