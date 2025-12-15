import random
from fastapi import APIRouter, Request, Form, Depends, BackgroundTasks
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from database import get_db
from models import User
from utils import get_password_hash, verify_password, create_access_token, send_brevo_email, send_welcome_email

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@router.get("/signup", response_class=HTMLResponse)
async def signup_page(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request})

@router.post("/auth/signup")
async def signup(background_tasks: BackgroundTasks, request: Request, email: str = Form(...), password: str = Form(...), password_confirm: str = Form(...), db: Session = Depends(get_db)):
    if password != password_confirm: return templates.TemplateResponse("signup.html", {"request": request, "error": "Şifreler uyuşmuyor."})
    if db.query(User).filter(User.email == email).first(): return templates.TemplateResponse("signup.html", {"request": request, "error": "Kayıtlı email."})
    
    code = str(random.randint(100000, 999999))
    new_user = User(email=email, password_hash=get_password_hash(password), verification_code=code)
    db.add(new_user); db.commit()
    
    background_tasks.add_task(send_brevo_email, email, "Doğrulama Kodu", f"<h1>Kod: {code}</h1>")
    return RedirectResponse(url=f"/verify?email={email}", status_code=303)

@router.get("/verify", response_class=HTMLResponse)
async def verify_page(request: Request, email: str):
    return templates.TemplateResponse("verify.html", {"request": request, "email": email})

@router.post("/auth/verify")
async def verify_code(background_tasks: BackgroundTasks, request: Request, email: str = Form(...), code: str = Form(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    if not user or user.verification_code != code: return templates.TemplateResponse("verify.html", {"request": request, "email": email, "error": "Hatalı kod."})
    user.is_verified = True; db.commit()
    background_tasks.add_task(send_welcome_email, email)
    return RedirectResponse(url="/login?msg=verified", status_code=303)

@router.post("/auth/login")
async def login(request: Request, email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(password, user.password_hash): return templates.TemplateResponse("login.html", {"request": request, "error": "Hatalı bilgi."})
    if not user.is_verified: return templates.TemplateResponse("login.html", {"request": request, "error": "Onaylanmamış hesap."})
    resp = RedirectResponse(url="/", status_code=303)
    resp.set_cookie(key="access_token", value=f"Bearer {create_access_token({'sub': user.email})}", httponly=True)
    return resp

@router.get("/logout")
async def logout():
    resp = RedirectResponse(url="/", status_code=303)
    resp.delete_cookie("access_token")
    return resp