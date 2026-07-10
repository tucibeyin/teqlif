from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func, cast, Date, text
from typing import List, Optional
from pydantic import BaseModel, Field
from datetime import datetime, timezone, timedelta

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.models.listing import Listing
from app.models.report import Report
from app.models.tuci_transaction import TuciTransaction
from app.models.ad_campaign import AdCampaign
from app.schemas.user import UserOut
from app.utils.auth import get_current_user, hash_password
from app.config import settings
from app.utils.redis_client import get_redis
from app.routers.chat import _publish_chat
from sqlalchemy.exc import IntegrityError
from app.core.exceptions import ForbiddenException, NotFoundException, BadRequestException
from app.core.logger import get_logger, capture_exception
from app.constants import ws_types as WS

logger = get_logger(__name__)

router = APIRouter(prefix="/api/admin-data", tags=["admin-data"])

# --- GÜVENLİK DUVARI ---
async def check_admin_access(current_user: User = Depends(get_current_user)):
    if not current_user.is_admin or current_user.email != settings.admin_email:
        raise ForbiddenException("Admin yetkisi bulunamadı.")
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
# 0. DASHBOARD
# ==========================================
@router.get("/dashboard")
async def get_dashboard(db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    today = datetime.now(timezone.utc).date()

    total_users = (await db.execute(select(func.count(User.id)))).scalar() or 0
    active_users = (await db.execute(select(func.count(User.id)).where(User.is_active == True))).scalar() or 0  # noqa: E712
    banned_users = (await db.execute(select(func.count(User.id)).where(User.is_active == False))).scalar() or 0  # noqa: E712
    tomorrow = today + timedelta(days=1)
    today_users = (await db.execute(
        select(func.count(User.id)).where(User.created_at >= today, User.created_at < tomorrow)
    )).scalar() or 0

    active_listings = (await db.execute(
        select(func.count(Listing.id)).where(Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
    )).scalar() or 0

    active_streams = (await db.execute(
        select(func.count(LiveStream.id)).where(LiveStream.is_live == True)  # noqa: E712
    )).scalar() or 0

    pending_reports = (await db.execute(
        select(func.count(Report.id))
    )).scalar() or 0

    total_tuci = (await db.execute(select(func.coalesce(func.sum(User.tuci_balance), 0)))).scalar() or 0

    today_tuci_spent = (await db.execute(
        select(func.coalesce(func.sum(TuciTransaction.amount), 0))
        .where(
            TuciTransaction.amount < 0,
            TuciTransaction.created_at >= today,
            TuciTransaction.created_at < tomorrow,
        )
    )).scalar() or 0

    # Son 7 gün günlük kayıt — growth chart için
    growth = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        day_end = day + timedelta(days=1)
        count = (await db.execute(
            select(func.count(User.id)).where(User.created_at >= day, User.created_at < day_end)
        )).scalar() or 0
        growth.append({"date": str(day), "count": count})

    return {
        "total_users": total_users,
        "active_users": active_users,
        "banned_users": banned_users,
        "today_users": today_users,
        "active_listings": active_listings,
        "active_streams": active_streams,
        "pending_reports": pending_reports,
        "total_tuci_circulation": total_tuci,
        "today_tuci_spent": abs(today_tuci_spent),
        "user_growth_7d": growth,
    }


# ==========================================
# 1. KULLANICI YÖNETİMİ
# ==========================================
@router.get("/users/recent")
async def get_recent_users(
    limit: int = 50,
    offset: int = 0,
    search: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access),
):
    base_q = select(User).where(User.deleted_at.is_(None))
    if search:
        term = f"%{search}%"
        base_q = base_q.where(
            User.username.ilike(term) | User.email.ilike(term) | User.full_name.ilike(term)
        )

    total_res = await db.execute(select(func.count()).select_from(base_q.subquery()))
    total = total_res.scalar() or 0

    result = await db.execute(base_q.order_by(desc(User.created_at)).limit(limit).offset(offset))
    users = result.scalars().all()

    user_ids = [u.id for u in users]
    listing_counts: dict = {}
    stream_counts: dict = {}
    if user_ids:
        listing_counts_res = await db.execute(
            select(Listing.user_id, func.count(Listing.id))
            .where(Listing.user_id.in_(user_ids), Listing.is_deleted == False)  # noqa: E712
            .group_by(Listing.user_id)
        )
        listing_counts = dict(listing_counts_res.all())

        stream_counts_res = await db.execute(
            select(LiveStream.host_id, func.count(LiveStream.id))
            .where(LiveStream.host_id.in_(user_ids))
            .group_by(LiveStream.host_id)
        )
        stream_counts = dict(stream_counts_res.all())

    return {
        "total": total,
        "users": [
            {
                "id": u.id,
                "username": u.username,
                "email": u.email,
                "full_name": u.full_name,
                "is_active": u.is_active,
                "is_verified": u.is_verified,
                "is_premium": u.is_premium,
                "plan_type": u.plan_type,
                "is_shadowbanned": u.is_shadowbanned,
                "deleted_at": u.deleted_at.isoformat() if u.deleted_at else None,
                "tuci_balance": u.tuci_balance,
                "fcm_token": bool(u.fcm_token),
                "created_at": u.created_at,
                "listing_count": listing_counts.get(u.id, 0),
                "stream_count": stream_counts.get(u.id, 0),
            }
            for u in users
        ],
    }

@router.patch("/users/{user_id}")
async def update_user_info(user_id: int, data: AdminUserUpdate, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı")
    if data.full_name is not None: user.full_name = data.full_name
    if data.email is not None: user.email = data.email
    if data.is_active is not None: user.is_active = data.is_active
    await db.commit()
    return {"message": "Bilgiler güncellendi."}

class ToggleProRequest(BaseModel):
    plan_type: Optional[str] = None

@router.post("/users/{user_id}/toggle-pro")
async def toggle_pro(
    user_id: int,
    req: ToggleProRequest,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access),
):
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı")
    user.is_premium = not user.is_premium
    if user.is_premium:
        user.plan_type = req.plan_type if req.plan_type else "monthly"
    else:
        user.plan_type = None
    await db.commit()
    status = "PRO verildi" if user.is_premium else "PRO kaldırıldı"
    logger.info("[ADMIN] %s → %s | admin=%s", user.username, status, admin.email)
    return {"user_id": user_id, "username": user.username, "is_premium": user.is_premium, "plan_type": user.plan_type}

@router.post("/users/{user_id}/shadowban")
async def toggle_shadowban(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access),
):
    """Kullanıcının shadowban durumunu tersine çevirir (toggle).
    Aynı zamanda Redis cache'ini geçersiz kılar, etki anında başlar."""
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı")
    user.is_shadowbanned = not user.is_shadowbanned
    await db.commit()
    # Redis cache'ini temizle — bir sonraki mesajda DB'den taze değer okunur
    try:
        redis = await get_redis()
        await redis.delete(f"shadowban:{user_id}")
    except Exception as exc:
        logger.warning("[ADMIN] shadowban Redis cache temizlenemedi | user_id=%s | %s", user_id, exc)
    status = "shadowbanned" if user.is_shadowbanned else "unshadowbanned"
    logger.info("[ADMIN] %s → %s | admin=%s", user.username, status, admin.email)
    return {"user_id": user_id, "username": user.username, "is_shadowbanned": user.is_shadowbanned}

@router.patch("/users/{user_id}/password")
async def reset_user_password(user_id: int, data: AdminPasswordReset, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı")
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
    try:
        redis = await get_redis()
    except Exception as exc:
        logger.warning("[ADMIN] Redis bağlantısı alınamadı, viewer count atlanıyor: %s", exc)
        redis = None

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
        raise BadRequestException("Yayın bulunamadı veya zaten kapalı")

    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)
    await db.commit()

    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{stream.room_name}")
        await _publish_chat(stream_id, {"type": WS.STREAM_ENDED, "message": "Yayın sistem yöneticisi tarafından sonlandırıldı."})
    except Exception as exc:
        logger.warning("[ADMIN] Redis temizleme/chat yayını başarısız | stream_id=%s | %s", stream_id, exc)
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
    if not listing: raise NotFoundException("İlan bulunamadı")
    listing.is_active = not listing.is_active
    await db.commit()
    return {"message": "İlan durumu değiştirildi."}

@router.delete("/listings/{listing_id}")
async def admin_delete_listing(listing_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    listing = await db.get(Listing, listing_id)
    if not listing: raise NotFoundException("İlan bulunamadı")
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
    if not report: raise NotFoundException("Şikayet bulunamadı")
    
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
        raise BadRequestException("E-posta veya kullanıcı adı zaten kullanımda.")

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


# Kullanıcı Silme (Soft Delete)
@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access),
):
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı.")

    if user.email == settings.admin_email:
        raise BadRequestException("Sistem yöneticisi silinemez.")

    if user.deleted_at is not None:
        raise BadRequestException("Kullanıcı zaten silinmiş.")

    now = datetime.now(timezone.utc)

    # Soft delete: hesabı kapat, token geçersiz kıl
    user.deleted_at = now
    user.is_active  = False
    user.fcm_token  = None   # push bildirimlerini durdur

    # Kullanıcının tüm aktif ilanlarını pasife çek
    await db.execute(
        Listing.__table__.update()
        .where(Listing.user_id == user_id)
        .values(is_active=False)
    )

    await db.commit()

    # Redis cache temizle
    try:
        redis = await get_redis()
        await redis.delete(
            f"interests:{user_id}",
            f"feed:{user_id}:0",
            f"shadowban:{user_id}",
        )
    except Exception:
        pass

    return {"message": f"Kullanıcı @{user.username} hesabı kapatıldı (soft delete)."}


# Kullanıcı Kalıcı Silme (Anonimize)
# Gerçek bir SQL DELETE mümkün değil: bids/listings/auctions/streams FK kısıtları kırar.
# Bunun yerine e-posta, kullanıcı adı ve telefon temizlenir → aynı bilgilerle yeniden kayıt açılabilir.
@router.post("/users/{user_id}/purge")
async def purge_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access),
):
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı.")

    if user.email == settings.admin_email:
        raise BadRequestException("Sistem yöneticisi silinemez.")

    old_username = user.username
    now = datetime.now(timezone.utc)

    # Kimlik bilgilerini temizle — FK satırları korunur
    user.email        = f"purged_{user_id}@deleted.invalid"
    user.username     = f"deleted_{user_id}"
    user.full_name    = "Silinmiş Hesap"
    user.phone        = None
    user.phone_verified = False
    user.hashed_password = ""
    user.avatar_url   = None
    user.bio          = None
    user.website_url  = None
    user.fcm_token    = None
    user.is_active    = False
    user.email_verified = False
    user.deleted_at   = user.deleted_at or now

    await db.commit()

    try:
        redis = await get_redis()
        await redis.delete(
            f"interests:{user_id}",
            f"feed:{user_id}:0",
            f"shadowban:{user_id}",
        )
    except Exception:
        pass

    return {"message": f"Kullanıcı @{old_username} kalıcı olarak silindi (anonimize)."}

# ==========================================
# 5. TUCi EKONOMİSİ
# ==========================================
class TuciAirdropRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    amount: int = Field(gt=0)
    note: str = ""

@router.get("/tuci/summary")
async def get_tuci_summary(limit: int = 100, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    total_circulation = (await db.execute(
        select(func.coalesce(func.sum(User.tuci_balance), 0))
    )).scalar() or 0

    total_spent = abs((await db.execute(
        select(func.coalesce(func.sum(TuciTransaction.amount), 0))
        .where(TuciTransaction.amount < 0)
    )).scalar() or 0)

    total_earned = (await db.execute(
        select(func.coalesce(func.sum(TuciTransaction.amount), 0))
        .where(TuciTransaction.amount > 0)
    )).scalar() or 0

    # Top 10 balance
    top_res = await db.execute(
        select(User.id, User.username, User.tuci_balance)
        .order_by(desc(User.tuci_balance))
        .limit(10)
    )
    top_holders = [{"user_id": r[0], "username": r[1], "balance": r[2]} for r in top_res.all()]

    # Recent transactions
    tx_res = await db.execute(
        select(TuciTransaction, User.username)
        .join(User, User.id == TuciTransaction.user_id)
        .order_by(desc(TuciTransaction.created_at))
        .limit(limit)
    )
    transactions = [
        {
            "id": tx.id,
            "username": username,
            "user_id": tx.user_id,
            "amount": tx.amount,
            "transaction_type": tx.transaction_type,
            "created_at": tx.created_at,
        }
        for tx, username in tx_res.all()
    ]

    return {
        "total_circulation": total_circulation,
        "total_spent": total_spent,
        "total_earned": total_earned,
        "top_holders": top_holders,
        "transactions": transactions,
    }

@router.post("/tuci/airdrop")
async def admin_tuci_airdrop(data: TuciAirdropRequest, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    result = await db.execute(select(User).where(User.username == data.username))
    user = result.scalar_one_or_none()
    if not user:
        raise NotFoundException(f"'{data.username}' kullanıcısı bulunamadı")
    # Atomic UPDATE — race condition'a karşı güvenli
    await db.execute(
        text("UPDATE users SET tuci_balance = tuci_balance + :amount WHERE id = :uid"),
        {"amount": data.amount, "uid": user.id},
    )
    db.add(TuciTransaction(user_id=user.id, amount=data.amount, transaction_type="airdrop"))
    await db.commit()
    await db.refresh(user)
    logger.info("[ADMIN] TUCi airdrop | user=%s | amount=%s | new_balance=%s | admin=%s", user.username, data.amount, user.tuci_balance, admin.email)
    return {"message": f"{user.username} kullanıcısına {data.amount} TUCi yüklendi.", "new_balance": user.tuci_balance, "username": user.username}


# ==========================================
# 6. REKLAM KAMPANYALARI
# ==========================================
@router.get("/ad-campaigns")
async def get_ad_campaigns(db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    res = await db.execute(
        select(AdCampaign, User.username, Listing.title)
        .join(User, User.id == AdCampaign.seller_id)
        .join(Listing, Listing.id == AdCampaign.listing_id)
        .order_by(desc(AdCampaign.created_at))
        .limit(100)
    )
    return [
        {
            "id": c.id,
            "username": username,
            "listing_title": listing_title,
            "listing_id": c.listing_id,
            "total_budget": c.total_budget,
            "spent_budget": c.spent_budget,
            "remaining": c.total_budget - c.spent_budget,
            "cpc_bid": c.cpc_bid,
            "status": c.status,
            "created_at": c.created_at,
        }
        for c, username, listing_title in res.all()
    ]

@router.post("/ad-campaigns/{campaign_id}/pause")
async def admin_pause_campaign(campaign_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    campaign = await db.get(AdCampaign, campaign_id)
    if not campaign:
        raise NotFoundException("Kampanya bulunamadı")
    campaign.status = "paused" if campaign.status == "active" else "active"
    await db.commit()
    return {"message": f"Kampanya durumu → {campaign.status}", "status": campaign.status}


# ==========================================
# 7. YAYIN GEÇMİŞİ
# ==========================================
@router.get("/streams/history")
async def get_stream_history(limit: int = 50, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    res = await db.execute(
        select(LiveStream, User.username)
        .join(User, User.id == LiveStream.host_id)
        .where(LiveStream.is_live == False)  # noqa: E712
        .order_by(desc(LiveStream.started_at))
        .limit(limit)
    )
    rows = []
    for stream, username in res.all():
        duration_min = None
        if stream.started_at and stream.ended_at:
            diff = stream.ended_at - stream.started_at
            duration_min = int(diff.total_seconds() / 60)
        rows.append({
            "id": stream.id,
            "title": stream.title,
            "category": stream.category,
            "host_username": username,
            "started_at": stream.started_at,
            "ended_at": stream.ended_at,
            "duration_min": duration_min,
            "viewer_count": stream.viewer_count,
        })
    return rows


# ==========================================
# 8. TOPLU PUSH BİLDİRİMİ
# ==========================================
class PushRequest(BaseModel):
    title: str
    body: str
    user_id: Optional[int] = None  # None = tüm kullanıcılar

@router.post("/push/send")
async def admin_send_push(data: PushRequest, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    from app.services.firebase_service import send_push

    if data.user_id:
        user = await db.get(User, data.user_id)
        if not user or not user.fcm_token:
            raise BadRequestException("Kullanıcı bulunamadı veya FCM token yok")
        await send_push(token=user.fcm_token, title=data.title, body=data.body, notif_type="admin_broadcast")
        logger.info("[ADMIN] Push gönderildi | user=%s | admin=%s", user.username, admin.email)
        return {"sent": 1}
    else:
        res = await db.execute(select(User.fcm_token).where(User.fcm_token.isnot(None), User.is_active == True))  # noqa: E712
        tokens = [r[0] for r in res.all() if r[0]]
        sent = 0
        for token in tokens:
            try:
                await send_push(token=token, title=data.title, body=data.body, notif_type="admin_broadcast")
                sent += 1
            except Exception:
                pass
        logger.info("[ADMIN] Toplu push | sent=%s/%s | admin=%s", sent, len(tokens), admin.email)
        return {"sent": sent, "total_tokens": len(tokens)}


# ==========================================
# 9. ANALİTİK VE ZİYARETÇİ VERİLERİ
# ==========================================
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

    recent_res = await db.execute(select(AnalyticsEvent).order_by(desc(AnalyticsEvent.created_at)).limit(500))
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
            "created_at": req.created_at,
            "metadata": req.event_metadata or {}
        })

    return {
        "total_events": total_events,
        "unique_sessions": unique_sessions,
        "device_stats": device_stats,
        "recent_events": recent_list
    }