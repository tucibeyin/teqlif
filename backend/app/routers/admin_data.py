from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, timezone

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.models.listing import Listing
from app.models.report import Report
from app.schemas.user import UserOut
from app.utils.auth import get_current_user, hash_password
from app.config import settings
from app.utils.redis_client import get_redis
from app.routers.chat import _publish_chat
from sqlalchemy.exc import IntegrityError

router = APIRouter(prefix="/api/admin-data", tags=["admin-data"])

# --- GÜVENLİK DUVARI ---
async def check_admin_access(current_user: User = Depends(get_current_user)):
    if current_user.email != settings.admin_email:
        raise HTTPException(status_code=403, detail="Admin yetkisi bulunamadı.")
    return current_user

# --- VERİ MODELLERİ (SCHEMAS) ---
class AdminUserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    is_active: Optional[bool] = None

class AdminPasswordReset(BaseModel):
    new_password: str

class AdminUserCreate(BaseModel):
    username: str
    email: str
    password: str
    full_name: Optional[str] = None

# ==========================================
# 1. KULLANICI YÖNETİMİ
# ==========================================
@router.get("/users/recent", response_model=List[UserOut])
async def get_recent_users(limit: int = 50, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(User).order_by(desc(User.created_at)).limit(limit))
    return result.scalars().all()

@router.patch("/users/{user_id}")
async def update_user_info(user_id: int, data: AdminUserUpdate, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
    if data.full_name is not None: user.full_name = data.full_name
    if data.email is not None: user.email = data.email
    if data.is_active is not None: user.is_active = data.is_active
    await db.commit()
    return {"message": "Bilgiler güncellendi."}

@router.patch("/users/{user_id}/password")
async def reset_user_password(user_id: int, data: AdminPasswordReset, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
    user.hashed_password = hash_password(data.new_password)
    await db.commit()
    return {"message": "Şifre değiştirildi."}

# ==========================================
# 2. CANLI YAYIN YÖNETİMİ
# ==========================================
@router.get("/streams/active")
async def get_admin_active_streams(db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(LiveStream).where(LiveStream.is_live == True).order_by(desc(LiveStream.started_at)))
    streams = result.scalars().all()
    stream_list = []
    try: redis = await get_redis()
    except: redis = None

    for s in streams:
        host = await db.get(User, s.host_id)
        viewer_count = 0
        if redis:
            count = await redis.get(f"live:viewers:{s.room_name}")
            viewer_count = int(count) if count else 0

        stream_list.append({
            "id": s.id, "room_name": s.room_name, "title": s.title,
            "host_username": host.username if host else "Bilinmiyor",
            "started_at": s.started_at, "viewer_count": viewer_count
        })
    return stream_list

@router.post("/streams/{stream_id}/end")
async def admin_end_stream(stream_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if not stream or not stream.is_live:
        raise HTTPException(status_code=400, detail="Yayın bulunamadı veya zaten kapalı")

    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)
    await db.commit()

    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{stream.room_name}")
        await _publish_chat(stream_id, {"type": "stream_ended", "message": "Yayın sistem yöneticisi tarafından sonlandırıldı."})
    except: pass
    return {"message": "Yayın kapatıldı."}

# ==========================================
# 3. İLAN YÖNETİMİ
# ==========================================
@router.get("/listings")
async def get_admin_listings(limit: int = 50, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(Listing).order_by(desc(Listing.created_at)).limit(limit))
    listings = result.scalars().all()
    
    data = []
    for l in listings:
        user = await db.get(User, l.user_id)
        data.append({
            "id": l.id, "title": l.title, "price": l.price,
            "is_active": l.is_active, "is_deleted": getattr(l, "is_deleted", False),
            "username": user.username if user else "Bilinmiyor", "created_at": l.created_at
        })
    return data

@router.post("/listings/{listing_id}/toggle")
async def admin_toggle_listing(listing_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    listing = await db.get(Listing, listing_id)
    if not listing: raise HTTPException(status_code=404, detail="İlan bulunamadı")
    listing.is_active = not listing.is_active
    await db.commit()
    return {"message": "İlan durumu değiştirildi."}

@router.delete("/listings/{listing_id}")
async def admin_delete_listing(listing_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    listing = await db.get(Listing, listing_id)
    if not listing: raise HTTPException(status_code=404, detail="İlan bulunamadı")
    listing.is_deleted = True
    listing.is_active = False
    await db.commit()
    return {"message": "İlan silindi."}

# ==========================================
# 4. ŞİKAYET (REPORT) YÖNETİMİ
# ==========================================
@router.get("/reports")
async def get_admin_reports(limit: int = 50, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(Report).order_by(desc(Report.created_at)).limit(limit))
    reports = result.scalars().all()
    
    data = []
    for r in reports:
        reporter = await db.get(User, r.reporter_id) if getattr(r, 'reporter_id', None) else None
        
        target_text = "Bilinmiyor"
        target_url = "#"

        if getattr(r, 'reported_id', None):
            u = await db.get(User, r.reported_id)
            target_text = f"@{u.username}" if u else "Kullanıcı"
            target_url = f"/profil/{u.username}" if u else "#"
        elif getattr(r, 'listing_id', None):
            target_text = f"İlan ID: {r.listing_id}"
            target_url = f"/ilan/{r.listing_id}"

        data.append({
            "id": r.id,
            "reporter": reporter.username if reporter else "Sistem",
            "reporter_url": f"/profil/{reporter.username}" if reporter else "#",
            "target": target_text,
            "target_url": target_url,
            "reason": r.reason,
            "status": getattr(r, 'status', 'pending'),
            "created_at": r.created_at
        })
    return data

@router.post("/reports/{report_id}/resolve")
async def admin_resolve_report(report_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    report = await db.get(Report, report_id)
    if not report: raise HTTPException(status_code=404, detail="Şikayet bulunamadı")
    
    if hasattr(report, 'status'):
        report.status = 'resolved'
        await db.commit()
    return {"message": "Şikayet çözüldü."}

@router.post("/users")
async def create_user(
    data: AdminUserCreate, 
    db: AsyncSession = Depends(get_db), 
    admin: User = Depends(check_admin_access)
):
    # E-posta veya kullanıcı adı kullanımda mı kontrolü
    existing_user = await db.execute(
        select(User).where((User.email == data.email) | (User.username == data.username))
    )
    if existing_user.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="E-posta veya kullanıcı adı zaten kullanımda.")

    # Yeni kullanıcıyı oluştur
    new_user = User(
        username=data.username,
        email=data.email,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        is_active=True
    )
    db.add(new_user)
    await db.commit()
    return {"message": f"Kullanıcı @{new_user.username} başarıyla oluşturuldu."}


# Kullanıcı Silme (Hard Delete)
@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int, 
    db: AsyncSession = Depends(get_db), 
    admin: User = Depends(check_admin_access)
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    
    # Admin kazara kendini silmesin diye güvenlik kilidi
    if user.email == settings.admin_email:
        raise HTTPException(status_code=400, detail="Sistem yöneticisi silinemez.")

    try:
        await db.delete(user)
        await db.commit()
        return {"message": "Kullanıcı veritabanından kalıcı olarak silindi."}
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400, 
            detail="Bu kullanıcı silinemez çünkü sisteme kayıtlı ilanları, mesajları veya canlı yayın geçmişi var. Bunun yerine hesabı 'Yasaklı' duruma getirin."
        )

# ==========================================
# 5. ANALİTİK VE ZİYARETÇİ VERİLERİ
# ==========================================
from sqlalchemy import func
from app.models.analytics import AnalyticsEvent

@router.get("/analytics/summary")
async def get_admin_analytics_summary(db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    total_events_res = await db.execute(select(func.count(AnalyticsEvent.id)))
    total_events = total_events_res.scalar() or 0

    unique_sessions_res = await db.execute(select(func.count(func.distinct(AnalyticsEvent.session_id))))
    unique_sessions = unique_sessions_res.scalar() or 0

    device_groups_res = await db.execute(
        select(AnalyticsEvent.device_type, func.count(AnalyticsEvent.id))
        .group_by(AnalyticsEvent.device_type)
    )
    device_stats = [{"device": item[0], "count": item[1]} for item in device_groups_res.all()]

    recent_res = await db.execute(select(AnalyticsEvent).order_by(desc(AnalyticsEvent.created_at)).limit(50))
    recent_events = recent_res.scalars().all()
    
    recent_list = []
    for req in recent_events:
        recent_list.append({
            "id": req.id,
            "session_id": req.session_id,
            "event_type": req.event_type,
            "url": req.url or "-",
            "device": req.device_type,
            "brand": req.os or req.browser or "-",
            "created_at": req.created_at
        })

    return {
        "total_events": total_events,
        "unique_sessions": unique_sessions,
        "device_stats": device_stats,
        "recent_events": recent_list
    }