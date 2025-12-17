import os
import shutil
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from database import engine, Base, SessionLocal
from models import User
from routers import auth, general, stream

# Veritabanı Tablolarını Oluştur
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Teqlif Live")

# Klasör Kontrolleri
os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/thumbnails", exist_ok=True)
os.makedirs("static/css", exist_ok=True)
os.makedirs("static/js", exist_ok=True)

# Başlangıçta eski yayın dosyalarını (video parçalarını) temizle
if os.path.exists("static/hls"):
    try:
        shutil.rmtree("static/hls", ignore_errors=True)
        os.makedirs("static/hls", exist_ok=True)
    except: pass

app.mount("/static", StaticFiles(directory="static"), name="static")

# Rotaları Dahil Et
app.include_router(auth.router)
app.include_router(general.router)
app.include_router(stream.router)

# 🔥 SİSTEM BAŞLARKEN VERİTABANINI TEMİZLE (Kalıcı Çözüm) 🔥
@app.on_event("startup")
def startup_db_cleanup():
    db = SessionLocal()
    try:
        # 'Yayında' görünen ama aslında kapalı olan (sunucu restart yemiş) kullanıcıları bul
        stuck_streams = db.query(User).filter(User.is_live == True).all()
        
        if stuck_streams:
            print(f"🧹 TEMİZLİK: {len(stuck_streams)} adet askıda kalan yayın kapatılıyor...")
            for user in stuck_streams:
                user.is_live = False
                user.is_auction_active = False
                user.current_price = 0
                user.highest_bidder = None
            db.commit()
            print("✅ Veritabanı temizlendi, sistem temiz başlıyor.")
        else:
            print("✅ Sistem temiz, askıda yayın yok.")
            
    except Exception as e:
        print(f"❌ Temizlik Hatası: {e}")
    finally:
        db.close()