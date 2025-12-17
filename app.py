import os
import shutil
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from database import engine, Base, SessionLocal
from models import User
from routers import auth, general, stream

# Create Database Tables
Base.metadata.create_all(bind=engine)

# Initialize App
app = FastAPI(title="Teqlif Live")

# Ensure Directories Exist
os.makedirs("static/hls", exist_ok=True)
os.makedirs("static/thumbnails", exist_ok=True)
os.makedirs("static/css", exist_ok=True)
os.makedirs("static/js", exist_ok=True)

# Initial Cleanup of HLS Files
if os.path.exists("static/hls"):
    try:
        shutil.rmtree("static/hls", ignore_errors=True)
        os.makedirs("static/hls", exist_ok=True)
    except: pass

# Mount Static Files
app.mount("/static", StaticFiles(directory="static"), name="static")

# Include Routers
app.include_router(auth.router)
app.include_router(general.router)
app.include_router(stream.router)

# 🔥 CRITICAL: AUTOMATIC DB CLEANUP ON STARTUP 🔥
@app.on_event("startup")
def startup_db_cleanup():
    db = SessionLocal()
    try:
        # Find streams marked as live but are actually stuck from a previous session
        stuck_streams = db.query(User).filter(User.is_live == True).all()
        
        if stuck_streams:
            print(f"🧹 CLEANUP: Closing {len(stuck_streams)} stuck streams...")
            for user in stuck_streams:
                user.is_live = False
                user.is_auction_active = False
                user.current_price = 0
                user.highest_bidder = None
            db.commit()
            print("✅ Database cleaned. System starting fresh.")
        else:
            print("✅ System clean. No stuck streams.")
            
    except Exception as e:
        print(f"❌ Cleanup Error: {e}")
    finally:
        db.close()