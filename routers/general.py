from typing import Optional
from fastapi import APIRouter, Request, Form, Depends
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db
from models import User
from utils import get_current_user

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/", response_class=HTMLResponse)
async def read_home(request: Request, category: Optional[str] = None, db: Session = Depends(get_db), user: Optional[User] = Depends(get_current_user)):
    # Sadece canlı olanları çek
    query = db.query(User).filter(User.is_live == True)
    
    # Eğer kategori seçildiyse ve 'Tümü' değilse filtrele
    if category and category != "Tümü":
        query = query.filter(User.stream_category == category)
        
    active_streams = query.all()
    
    # Takip ettiklerini öne al
    if user:
        followed_ids = [u.id for u in user.followed]
        active_streams.sort(key=lambda x: x.id not in followed_ids)
        
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "user": user, 
        "streams": active_streams,
        "current_category": category if category else "Tümü" # Seçili kategoriyi template'e gönder
    })

@router.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, user: Optional[User] = Depends(get_current_user)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    return templates.TemplateResponse("settings.html", {"request": request, "user": user})

@router.post("/settings/update")
async def update_profile(request: Request, username: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return RedirectResponse(url="/login", status_code=303)
    existing = db.query(User).filter(User.username == username).first()
    if existing and existing.id != user.id:
        return templates.TemplateResponse("settings.html", {"request": request, "user": user, "error": "Bu kullanıcı adı alınmış."})
    user.username = username; db.commit()
    return templates.TemplateResponse("settings.html", {"request": request, "user": user, "success": "Güncellendi."})

# 🔥 YENİ: ELMAS SATIN ALMA API 🔥
@router.post("/settings/buy_diamonds")
async def buy_diamonds(amount: int = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return JSONResponse({"status": "error", "msg": "Giriş yapmalısınız"}, 401)
    
    # Geçerli paketleri kontrol et (Güvenlik)
    valid_packages = [10, 50, 100, 1000, 5000]
    if amount not in valid_packages:
        return JSONResponse({"status": "error", "msg": "Geçersiz paket seçimi"}, 400)
    
    # ÖDEME SİMÜLASYONU (Burada normalde kredi kartı çekimi olur)
    # 1 Diamond = 1 TL
    cost = amount * 1 
    
    # Başarılı sayıyoruz ve elması yüklüyoruz
    user.diamonds += amount
    db.commit()
    
    return JSONResponse({"status": "success", "new_balance": user.diamonds, "msg": f"{amount} Elmas başarıyla yüklendi!"})

@router.post("/user/follow")
async def follow_user(username: str = Form(...), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user: return JSONResponse({"status": "error"}, 401)
    target = db.query(User).filter(User.username == username).first()
    if not target or target.id == user.id: return JSONResponse({"status": "error"}, 400)
    
    if target not in user.followed:
        user.followed.append(target); db.commit(); return JSONResponse({"status": "followed"})
    else:
        user.followed.remove(target); db.commit(); return JSONResponse({"status": "unfollowed"})