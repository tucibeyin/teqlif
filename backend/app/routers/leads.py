"""
Lead Generation (Sıcak Talep & Kitle Satışı) Router

GET  /api/leads/audience-size  — Son 7 gün içinde ilgili ilanları gören eşsiz kullanıcı sayısı
GET  /api/leads/blast-credits  — Aylık blast kredi durumu
POST /api/leads/send-blast     — Hedef kitleye push bildirimi gönder
"""
from __future__ import annotations

import asyncio
import calendar
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, text as sql_text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, AsyncSessionLocal
from app.models.listing import Listing
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.utils.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/leads", tags=["leads"])

COST_PER_PERSON: int = 10        # TUCi per kişi
_BLAST_LIMIT_STANDARD = 3        # aylık ücretsiz alıcı hakkı
_BLAST_LIMIT_PRO      = 6        # aylık ücretsiz alıcı hakkı (PRO)
_PER_BLAST_CAP_STANDARD = 5      # tek blast'ta maks. alıcı
_PER_BLAST_CAP_PRO      = 10     # tek blast'ta maks. alıcı (PRO)


# ── Blast Kredi Yardımcıları (Redis) ─────────────────────────────────────────

def _blast_redis_key(user_id: int) -> str:
    month = datetime.now().strftime("%Y-%m")
    return f"blast_credits:{user_id}:{month}"


async def _get_blast_used(user_id: int) -> int:
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        val = await redis.get(_blast_redis_key(user_id))
        return int(val) if val else 0
    except Exception:
        return 0


async def _increment_blast(user_id: int, count: int = 1) -> None:
    """Kullanılan ücretsiz alıcı sayısını Redis'e yazar (INCRBY)."""
    if count <= 0:
        return
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        key = _blast_redis_key(user_id)
        new_val = await redis.incrby(key, count)
        if new_val <= count:
            # Anahtar bu ay ilk kez oluşturuldu — ayın sonuna TTL ayarla
            now = datetime.now()
            last_day = calendar.monthrange(now.year, now.month)[1]
            end_of_month = datetime(now.year, now.month, last_day, 23, 59, 59)
            ttl_secs = int((end_of_month - now).total_seconds()) + 1
            await redis.expire(key, ttl_secs)
    except Exception:
        pass


# ── Kitle Büyüklüğü ──────────────────────────────────────────────────────────

@router.get("/audience-size")
async def audience_size(
    title: str = Query(..., min_length=2, max_length=200),
    category: str = Query(default=""),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Bu başlık/kategori ile eşleşen ve son 7 gün içinde aktif olan,
    FCM token'ı bulunan gerçek kullanıcı sayısını döndürür.
    send-blast ile aynı mantık kullanılır — tahmin yoktur.
    """
    listing_q = select(Listing.id).where(
        Listing.is_deleted == False,  # noqa: E712
        Listing.is_active == True,    # noqa: E712
    )
    if category:
        listing_q = listing_q.where(Listing.category == category)
    listing_q = listing_q.limit(500)

    result = await db.execute(listing_q)
    listing_ids: list[int] = [row[0] for row in result.fetchall()]

    if not listing_ids:
        return {"audience_size": 0, "estimated_cost": 0}

    # ClickHouse'dan gerçek user_id listesi (tahmin değil)
    ids_str = ", ".join(str(i) for i in listing_ids)
    target_user_ids: list[int] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(f"""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_type = 'listing'
              AND item_id IN ({ids_str})
              AND event_type IN ('view', 'dwell', 'bid_hesitation')
              AND timestamp >= now() - INTERVAL 7 DAY
              AND user_id IS NOT NULL
              AND user_id != {current_user.id}
            LIMIT 10001
        """)
        target_user_ids = [int(r[0]) for r in ch_result.result_rows if r[0]]
    except Exception as exc:
        logger.warning("[Leads] ClickHouse sorgusu başarısız: %s", exc)

    audience_capped = len(target_user_ids) > 10000
    target_user_ids = target_user_ids[:10000]

    # PostgreSQL'den gerçek FCM token sayısı — takipçiler hariç
    if target_user_ids:
        token_count = await db.scalar(sql_text("""
            SELECT COUNT(*) FROM users
            WHERE id = ANY(:ids)
              AND fcm_token IS NOT NULL AND fcm_token != ''
              AND id NOT IN (
                  SELECT follower_id FROM follows WHERE followed_id = :me
              )
        """), {"ids": target_user_ids, "me": current_user.id})
        reachable = int(token_count or 0)
    else:
        reachable = 0

    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    used  = await _get_blast_used(current_user.id)
    credits_remaining = max(0, limit - used)

    actual_cap      = min(reachable, cap)
    free_used       = min(credits_remaining, actual_cap)
    paid_count      = actual_cap - free_used
    estimated_cost  = paid_count * COST_PER_PERSON

    return {
        "audience_size":          reachable,
        "non_follower_audience":  reachable,
        "estimated_cost":         estimated_cost,
        "audience_capped":        audience_capped,
        "per_blast_cap":          cap,
        "credits_remaining":      credits_remaining,
        "tuci_balance":           current_user.tuci_balance,
    }


# ── Blast Kredi Durumu ────────────────────────────────────────────────────────

@router.get("/blast-credits")
async def blast_credits(
    current_user: User = Depends(get_current_user),
):
    """Kullanıcının bu ayki blast kredi durumunu döndürür."""
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    used  = await _get_blast_used(current_user.id)
    return {
        "used":          used,
        "limit":         limit,
        "remaining":     max(0, limit - used),
        "is_premium":    current_user.is_premium,
        "per_blast_cap": cap,
        "tuci_balance":  current_user.tuci_balance,
    }


# ── Push Blast Gönder ─────────────────────────────────────────────────────────

class BlastRequest(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    category: str = Field(default="")
    listing_id: int | None = Field(default=None)
    stream_id: int | None = Field(default=None)
    estimated_cost: int = Field(ge=0)
    recipient_count: int | None = Field(default=None, ge=1)  # kullanıcının seçtiği alıcı sayısı


@router.post("/send-blast", status_code=202)
async def send_blast(
    body: BlastRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Hedef kitleye push bildirimi gönderir.

    Karma model: free_used kredi ücretsiz, kalan paid_count × 10 TUCi.
    1. Kredi + per_blast_cap → actual alıcı sayısı belirlenir.
    2. ClickHouse → son 7 günde aktif user_id listesi (takipçiler hariç).
    3. PostgreSQL → FCM tokenları al.
    4. Firebase → toplu push gönder.
    """
    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    used  = await _get_blast_used(current_user.id)
    credits_remaining = max(0, limit - used)

    # Kullanıcının seçtiği ya da maksimum alıcı sayısı
    desired = body.recipient_count if body.recipient_count else cap
    actual_count = min(desired, cap)

    # Karma maliyet hesabı
    free_used  = min(credits_remaining, actual_count)
    paid_count = actual_count - free_used
    tuci_cost  = paid_count * COST_PER_PERSON

    # ── TUCi bakiye kontrolü ─────────────────────────────────────────────────
    if tuci_cost > 0 and current_user.tuci_balance < tuci_cost:
        raise HTTPException(
            status_code=402,
            detail=f"Yetersiz TUCi bakiyesi. Mevcut: {current_user.tuci_balance} TUCi, Gerekli: {tuci_cost} TUCi",
        )

    # ── Kategorideki listing ID'leri ─────────────────────────────────────────
    listing_q = select(Listing.id).where(
        Listing.is_deleted == False,  # noqa: E712
        Listing.is_active == True,    # noqa: E712
    )
    if body.category:
        listing_q = listing_q.where(Listing.category == body.category)
    listing_q = listing_q.limit(500)
    listing_result = await db.execute(listing_q)
    listing_ids = [r[0] for r in listing_result.fetchall()]

    if not listing_ids:
        raise HTTPException(status_code=404, detail="Hedef kitle bulunamadı.")

    # ── ClickHouse: aktif user_id listesi ────────────────────────────────────
    ids_str = ", ".join(str(i) for i in listing_ids)
    target_user_ids: list[int] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(f"""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_type = 'listing'
              AND item_id IN ({ids_str})
              AND event_type IN ('view', 'dwell', 'bid_hesitation')
              AND timestamp >= now() - INTERVAL 7 DAY
              AND user_id IS NOT NULL
              AND user_id != {current_user.id}
            LIMIT 10000
        """)
        target_user_ids = [int(r[0]) for r in ch_result.result_rows if r[0]]
    except Exception as exc:
        logger.warning("[Leads] ClickHouse user listesi alınamadı: %s", exc)

    # ── PostgreSQL: FCM tokenlar ──────────────────────────────────────────────
    if not target_user_ids:
        logger.info("[Leads] ClickHouse verisi yok — blast iptal | seller=%d", current_user.id)
        return {"sent": 0, "spent": 0, "message": "Bu kategori için henüz yeterli kitle verisi yok."}

    token_result = await db.execute(sql_text("""
        SELECT fcm_token FROM users
        WHERE id = ANY(:ids)
          AND fcm_token IS NOT NULL AND fcm_token != ''
          AND id NOT IN (
              SELECT follower_id FROM follows WHERE followed_id = :me
          )
        LIMIT :cap
    """), {"ids": target_user_ids, "me": current_user.id, "cap": actual_count})
    fcm_tokens: list[str] = [r[0] for r in token_result.fetchall() if r[0]]

    if not fcm_tokens:
        logger.info("[Leads] FCM token bulunamadı — blast iptal | seller=%d", current_user.id)
        return {
            "sent": 0,
            "spent": 0,
            "message": "Bu hedef kitlede bildirim alacak kullanıcı bulunamadı.",
        }

    # ── Firebase toplu push (fire-and-forget) ─────────────────────────────────
    from app.services.firebase_service import send_push, InvalidFCMTokenError

    if body.stream_id:
        listing_url = f"/yayin?id={body.stream_id}"
    elif body.listing_id:
        listing_url = f"/ilan/{body.listing_id}"
    else:
        listing_url = "/home"

    async def _send_one(token: str) -> None:
        try:
            await send_push(
                token=token,
                title="🔥 Aradığın ürün şu an satışta!",
                body=f'"{body.title}" — Kaçırmadan incele!',
                notif_type="lead_blast",
                extra_data={"url": listing_url},
            )
        except InvalidFCMTokenError:
            logger.info("[Leads] Geçersiz FCM token temizlendi")
        except Exception as exc:
            logger.warning("[Leads] Push başarısız: %s", exc)

    chunk_size = 50
    sent = 0
    for i in range(0, len(fcm_tokens), chunk_size):
        chunk = fcm_tokens[i : i + chunk_size]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)

    logger.info(
        "[Leads] Blast gönderildi | seller=%d | tokens=%d | free=%d | paid=%d | cost=%d TUCi",
        current_user.id, sent, free_used, paid_count, tuci_cost,
    )

    # ── TUCi düş + kredi say ──────────────────────────────────────────────────
    if tuci_cost > 0:
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_lead_gen",
        ))
        await db.commit()

    if free_used > 0:
        await _increment_blast(current_user.id, count=free_used)

    return {
        "sent": sent,
        "spent": tuci_cost,
        "message": f"{sent} kişiye bildirim gönderildi.",
    }


# ── Retargeting ───────────────────────────────────────────────────────────────

@router.get("/retargeting-audience/{listing_id}")
async def retargeting_audience(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    PRO: İlanı görüntüleyen ama satın almayan kullanıcı sayısını döner.
    ClickHouse feed_analytics + user_events tablosundan çekilir.
    """
    if not current_user.is_premium:
        raise HTTPException(403, "Bu özellik yalnızca PRO kullanıcılara açıktır")

    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise HTTPException(404, "İlan bulunamadı")

    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()

        # ClickHouse: görüntüleyen eşsiz user_id listesi (son 30 gün)
        vid_result = await ch.query("""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_id = %(lid)s
              AND event_type IN ('view', 'dwell', 'detail_dwell', 'click')
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id != %(uid)s
              AND user_id != 0
            LIMIT 500
        """, parameters={"lid": listing_id, "uid": current_user.id})
        viewer_ids = [int(r[0]) for r in vid_result.result_rows]
        total_viewers = len(viewer_ids)

        # Kazanılan açık artırma sayısı (purchases çift sayımını önlemek için sadece auctions kullan)
        buyer_result = await db.scalar(sql_text("""
            SELECT COUNT(*) FROM auctions
            WHERE listing_id = :lid AND winner_username IS NOT NULL AND status = 'completed'
        """), {"lid": listing_id})
        already_bought = int(buyer_result or 0)

        # Gerçek FCM token sayısını say — takipçiler hariç
        if viewer_ids:
            token_count = await db.scalar(sql_text("""
                SELECT COUNT(*) FROM users
                WHERE id = ANY(:ids)
                  AND fcm_token IS NOT NULL AND fcm_token != ''
                  AND id NOT IN (
                      SELECT follower_id FROM follows WHERE followed_id = :me
                  )
            """), {"ids": viewer_ids, "me": current_user.id})
            reachable_with_token = int(token_count or 0)
        else:
            reachable_with_token = 0

        cap   = _PER_BLAST_CAP_PRO
        used  = await _get_blast_used(current_user.id)
        credits_remaining = max(0, _BLAST_LIMIT_PRO - used)
        actual_cap   = min(reachable_with_token, cap)
        free_used    = min(credits_remaining, actual_cap)
        paid_count   = actual_cap - free_used
        estimated_cost = paid_count * COST_PER_PERSON

        return {
            "listing_id": listing_id,
            "listing_title": listing.title,
            "total_viewers_30d": total_viewers,
            "already_bought": already_bought,
            "reachable_audience": reachable_with_token,
            "non_follower_audience": reachable_with_token,
            "estimated_cost_tuci": estimated_cost,
            "blast_credits_remaining": credits_remaining,
            "blast_credits_limit": _BLAST_LIMIT_PRO,
            "per_blast_cap": cap,
            "tuci_balance": current_user.tuci_balance,
        }

    except Exception as exc:
        logger.warning("[Retargeting] audience-size başarısız: %s", exc)
        return {
            "listing_id": listing_id,
            "listing_title": listing.title,
            "total_viewers_30d": 0,
            "already_bought": 0,
            "reachable_audience": 0,
            "non_follower_audience": 0,
            "estimated_cost_tuci": 0,
            "blast_credits_remaining": 0,
            "blast_credits_limit": _BLAST_LIMIT_PRO,
            "per_blast_cap": _PER_BLAST_CAP_PRO,
            "tuci_balance": current_user.tuci_balance,
        }


class RetargetingBlastBody(BaseModel):
    listing_id: int
    estimated_audience: int = Field(ge=0)
    estimated_cost: int = Field(ge=0)
    recipient_count: int | None = Field(default=None, ge=1)  # kullanıcının seçtiği alıcı sayısı


@router.post("/send-retargeting")
async def send_retargeting(
    body: RetargetingBlastBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    PRO: İlanı görüntüleyen ama satın almayan kullanıcılara kişiselleştirilmiş bildirim gönderir.
    1 TUCi per kişi (blast kredi sayımına dahil edilmez — ayrı bir işlem).
    """
    if not current_user.is_premium:
        raise HTTPException(403, "Bu özellik yalnızca PRO kullanıcılara açıktır")

    listing = await db.scalar(
        select(Listing).where(Listing.id == body.listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise HTTPException(404, "İlan bulunamadı")

    # Karma model: kredi ücretsiz, kalan × 10 TUCi
    cap   = _PER_BLAST_CAP_PRO
    used  = await _get_blast_used(current_user.id)
    credits_remaining = max(0, _BLAST_LIMIT_PRO - used)

    desired      = body.recipient_count if body.recipient_count else cap
    actual_count = min(desired, cap)
    free_used    = min(credits_remaining, actual_count)
    paid_count   = actual_count - free_used
    tuci_cost    = paid_count * COST_PER_PERSON

    if tuci_cost > 0 and current_user.tuci_balance < tuci_cost:
        raise HTTPException(402, f"Yetersiz TUCi bakiyesi. Mevcut: {current_user.tuci_balance} TUCi, Gerekli: {tuci_cost} TUCi")

    # ClickHouse'dan viewer user_id'lerini çek
    viewer_ids: list[int] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        result = await ch.query("""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_id = %(lid)s
              AND event_type IN ('view', 'dwell', 'detail_dwell', 'click')
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id != %(uid)s
              AND user_id != 0
            LIMIT 500
        """, parameters={"lid": body.listing_id, "uid": current_user.id})
        viewer_ids = [int(r[0]) for r in result.result_rows]
    except Exception as exc:
        logger.warning("[Retargeting] ClickHouse viewer query başarısız: %s", exc)

    if not viewer_ids:
        return {"sent": 0, "spent": 0, "message": "Henüz yeterli izleyici verisi yok."}

    # FCM token'ları PostgreSQL'den çek — takipçiler hariç, actual_count ile sınırlı
    token_rows = (await db.execute(sql_text("""
        SELECT fcm_token FROM users
        WHERE id = ANY(:ids)
          AND fcm_token IS NOT NULL AND fcm_token != ''
          AND id NOT IN (
              SELECT follower_id FROM follows WHERE followed_id = :me
          )
        LIMIT :cap
    """), {"ids": viewer_ids, "me": current_user.id, "cap": actual_count})).fetchall()
    fcm_tokens = [r[0] for r in token_rows]

    if not fcm_tokens:
        return {"sent": 0, "spent": 0, "message": "Bildirim gönderilebilecek kullanıcı bulunamadı."}

    listing_url = f"/listing/{body.listing_id}"

    from app.services.firebase_service import send_push, InvalidFCMTokenError

    async def _send_one(token: str) -> None:
        try:
            await send_push(
                token=token,
                title="Hâlâ ilgilendin mi? 👀",
                body=f"{listing.title} — hâlâ satışta!",
                data={"type": "new_listing", "listing_id": str(body.listing_id)},
                extra_data={"url": listing_url},
            )
        except InvalidFCMTokenError:
            pass
        except Exception as exc:
            logger.warning("[Retargeting] Push başarısız: %s", exc)

    sent = 0
    for i in range(0, len(fcm_tokens), 50):
        chunk = fcm_tokens[i: i + 50]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)

    # TUCi düş + kredi say
    if tuci_cost > 0:
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_retargeting",
        ))
        await db.commit()

    if free_used > 0:
        await _increment_blast(current_user.id, count=free_used)

    logger.info("[Retargeting] Gönderildi | seller=%d | sent=%d | free=%d | paid=%d | cost=%d TUCi",
                current_user.id, sent, free_used, paid_count, tuci_cost)

    return {
        "sent": sent,
        "spent": tuci_cost,
        "message": f"{sent} kişiye geri hedefleme bildirimi gönderildi.",
    }
