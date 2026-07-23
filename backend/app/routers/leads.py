"""
Lead Generation (Sıcak Talep & Kitle Satışı) Router

GET  /api/leads/audience-size  — Son 7 gün içinde ilgili ilanları gören eşsiz kullanıcı sayısı
GET  /api/leads/blast-credits  — Aylık blast kredi durumu
POST /api/leads/send-blast     — Hedef kitleye push bildirimi gönder
"""
from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Depends, Query
from app.core.exceptions import NotFoundException, ForbiddenException, InsufficientFundsException
from app.services import credit_service
from pydantic import BaseModel, Field
from sqlalchemy import select, text as sql_text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import ListingStatus
from app.database import get_db, AsyncSessionLocal
from app.models.listing import Listing
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.utils.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/leads", tags=["leads"])


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
        Listing.status != ListingStatus.DELETED,  # noqa: E712
        Listing.status == ListingStatus.ACTIVE,    # noqa: E712
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
              AND timestamp >= now() - INTERVAL 30 DAY
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

    cap   = credit_service.per_op_cap("blast", current_user.is_premium)
    limit = credit_service.free_limit("blast", current_user.is_premium)
    used  = await credit_service.get_used("blast", current_user.id, current_user.premium_since)
    credits_remaining = max(0, limit - used)

    actual_cap      = min(reachable, cap)
    free_used       = min(credits_remaining, actual_cap)
    paid_count      = actual_cap - free_used
    estimated_cost  = paid_count * credit_service.cost_tuci("blast")

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
    limit = credit_service.free_limit("blast", current_user.is_premium)
    cap   = credit_service.per_op_cap("blast", current_user.is_premium)
    used  = await credit_service.get_used("blast", current_user.id, current_user.premium_since)
    renewal_date: str | None = None
    if current_user.premium_since:
        renewal_date = credit_service.next_billing_date(current_user.premium_since).isoformat()
    return {
        "used":          used,
        "limit":         limit,
        "remaining":     max(0, limit - used),
        "is_premium":    current_user.is_premium,
        "per_blast_cap": cap,
        "tuci_balance":  current_user.tuci_balance,
        "renewal_date":  renewal_date,
    }


# ── Push Blast Gönder ─────────────────────────────────────────────────────────

class BlastRequest(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    category: str = Field(default="")
    listing_id: int | None = Field(default=None)
    stream_id: int | None = Field(default=None)
    estimated_cost: int | None = Field(default=None, ge=0)
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
    cap   = credit_service.per_op_cap("blast", current_user.is_premium)
    limit = credit_service.free_limit("blast", current_user.is_premium)
    used  = await credit_service.get_used("blast", current_user.id, current_user.premium_since)
    credits_remaining = max(0, limit - used)

    # İstenen maksimum kişi sayısı
    # estimated_cost is None → alan gönderilmemiş, tam cap kullan (eski caller'lar).
    # estimated_cost >= 0 → kullanıcının onayladığı fatura tavanı; bu kadarı geçme.
    desired = body.recipient_count if body.recipient_count else cap
    if body.estimated_cost is not None:
        max_paid_authorized = body.estimated_cost // credit_service.cost_tuci("blast")
        actual_count_max = min(desired, credits_remaining + max_paid_authorized, cap)
    else:
        actual_count_max = min(desired, cap)

    # ── Kategorideki listing ID'leri ─────────────────────────────────────────
    listing_q = select(Listing.id).where(
        Listing.status != ListingStatus.DELETED,
        Listing.status == ListingStatus.ACTIVE,
    )
    if body.category:
        listing_q = listing_q.where(Listing.category == body.category)
    listing_q = listing_q.limit(500)
    listing_result = await db.execute(listing_q)
    listing_ids = [r[0] for r in listing_result.fetchall()]

    if not listing_ids:
        return {"error": "Hedef kitle bulunamadı."}

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
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id IS NOT NULL
              AND user_id != {current_user.id}
            LIMIT 10000
        """)
        target_user_ids = [int(r[0]) for r in ch_result.result_rows if r[0]]
    except Exception as exc:
        logger.warning("[Leads] ClickHouse user listesi alınamadı: %s", exc)

    if not target_user_ids:
        return {"error": "Bildirim atılabilecek aktif cihaz bulunamadı."}

    # ── PostgreSQL: hedef kullanıcılar + FCM tokenlar ───────────────────────────
    # Opt-out eden PRO kullanıcılar: in-app bildirim alır, push almaz.
    recipient_result = await db.execute(sql_text("""
        SELECT id, fcm_token,
               (notification_prefs->>'receive_blast_notifications')::boolean AS receive_push
        FROM users
        WHERE id = ANY(:ids)
          AND id NOT IN (
              SELECT follower_id FROM follows WHERE followed_id = :me
          )
        LIMIT :cap
    """), {"ids": target_user_ids, "me": current_user.id, "cap": actual_count_max})
    rows = recipient_result.fetchall()

    recipient_ids: list[int] = [r[0] for r in rows]
    # receive_push NULL (yeni kayıt, henüz pref set edilmemiş) → True kabul et
    fcm_tokens: list[str] = [
        r[1] for r in rows
        if r[1] and r[2] is not False
    ]

    # GERÇEK (ACTUAL) ALICI SAYISI
    actual_count = len(recipient_ids)

    if actual_count == 0:
        return {"error": "Bildirim atılabilecek aktif cihaz bulunamadı."}

    # ── Kesin Maliyet Hesabı (Sadece Bulunan FCM Sayısına Göre) ─────────────
    free_used  = min(credits_remaining, actual_count)
    paid_count = actual_count - free_used
    tuci_cost  = paid_count * credit_service.cost_tuci("blast")

    # ── TUCi bakiye kontrolü ─────────────────────────────────────────────────
    if tuci_cost > 0 and current_user.tuci_balance < tuci_cost:
        return {"error": f"Yetersiz TUCi bakiyesi. Mevcut: {current_user.tuci_balance} TUCi, Gerekli: {tuci_cost} TUCi"}

    # ── Kampanya Kaydı Oluştur ────────────────────────────────────────────────
    from app.models.mass_notification import MassNotificationCampaign
    
    campaign = MassNotificationCampaign(
        user_id=current_user.id,
        listing_id=body.listing_id,
        stream_id=body.stream_id,
        target_count=actual_count,
        sent_count=0, # Asıl gönderimde güncellenir
        click_count=0,
        spent_tuci=tuci_cost,
        spent_free_credits=free_used,
    )
    db.add(campaign)
    await db.flush() # get campaign.id

    # ── TUCi düş ──────────────────────────────────────────────────────────────
    if tuci_cost > 0:
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_lead_gen",
            reference_id=body.listing_id,
            reference_type="listing",
        ))
    
    await db.commit()

    if free_used > 0:
        await credit_service.increment("blast", current_user.id, current_user.premium_since, count=free_used)

    # ── In-app bildirim kayıtları (tüm alıcılar — push almayacaklar dahil) ─────
    from app.models.notification import Notification
    notif_title = "🔥 Aradığın ürün şu an satışta!"
    notif_body  = f'"{body.title}" — Kaçırmadan incele!'
    db.add_all([
        Notification(
            user_id=uid,
            type="lead_blast",
            title=notif_title,
            body=notif_body,
            related_id=body.listing_id,
        )
        for uid in recipient_ids
    ])
    await db.commit()

    # ── Firebase toplu push (push almak isteyenler için) ──────────────────────
    from app.services.firebase_service import send_push, InvalidFCMTokenError

    async def _send_one(token: str, cid: int) -> None:
        try:
            extra_data = {"campaign_id": str(cid)}
            if body.listing_id:
                extra_data["listing_id"] = str(body.listing_id)
            if body.stream_id:
                extra_data["stream_id"] = str(body.stream_id)
            await send_push(
                token=token,
                title=notif_title,
                body=notif_body,
                notif_type="lead_blast",
                extra_data=extra_data,
            )
        except InvalidFCMTokenError:
            pass
        except Exception:
            pass

    chunk_size = 50
    sent = 0
    for i in range(0, len(fcm_tokens), chunk_size):
        chunk = fcm_tokens[i : i + chunk_size]
        await asyncio.gather(*[_send_one(t, campaign.id) for t in chunk])
        sent += len(chunk)

    await db.execute(
        sql_text("UPDATE mass_notification_campaigns SET sent_count = :sent WHERE id = :cid"),
        {"sent": actual_count, "cid": campaign.id}
    )
    await db.commit()

    return {
        "campaign_id": campaign.id,
        "sent": actual_count,
        "spent": tuci_cost,
        "message": f"{actual_count} kişiye bildirim gönderildi.",
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
        raise ForbiddenException(code="PRO_REQUIRED")

    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise NotFoundException()

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

        cap   = credit_service.per_op_cap("blast", is_premium=True)
        used  = await credit_service.get_used("blast", current_user.id, current_user.premium_since)
        credits_remaining = max(0, credit_service.free_limit("blast", is_premium=True) - used)
        actual_cap   = min(reachable_with_token, cap)
        free_used    = min(credits_remaining, actual_cap)
        paid_count   = actual_cap - free_used
        estimated_cost = paid_count * credit_service.cost_tuci("blast")

        return {
            "listing_id": listing_id,
            "listing_title": listing.title,
            "total_viewers_30d": total_viewers,
            "already_bought": already_bought,
            "reachable_audience": reachable_with_token,
            "non_follower_audience": reachable_with_token,
            "estimated_cost_tuci": estimated_cost,
            "blast_credits_remaining": credits_remaining,
            "blast_credits_limit": credit_service.free_limit("blast", is_premium=True),
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
            "blast_credits_limit": credit_service.free_limit("blast", is_premium=True),
            "per_blast_cap": credit_service.per_op_cap("blast", is_premium=True),
            "tuci_balance": current_user.tuci_balance,
        }


class RetargetingBlastBody(BaseModel):
    listing_id: int
    estimated_audience: int | None = Field(default=None, ge=0)
    estimated_cost: int | None = Field(default=None, ge=0)
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
        raise ForbiddenException(code="PRO_REQUIRED")

    listing = await db.scalar(
        select(Listing).where(Listing.id == body.listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise NotFoundException()

    # Karma model: kredi ücretsiz, kalan × 10 TUCi
    cap   = credit_service.per_op_cap("blast", is_premium=True)
    used  = await credit_service.get_used("blast", current_user.id, current_user.premium_since)
    credits_remaining = max(0, credit_service.free_limit("blast", is_premium=True) - used)

    desired = body.recipient_count if body.recipient_count else cap
    if body.estimated_cost is not None:
        max_paid_authorized = body.estimated_cost // credit_service.cost_tuci("blast")
        actual_count = min(desired, credits_remaining + max_paid_authorized, cap)
    else:
        actual_count = min(desired, cap)
    free_used    = min(credits_remaining, actual_count)
    paid_count   = actual_count - free_used
    tuci_cost    = paid_count * credit_service.cost_tuci("blast")

    if tuci_cost > 0 and current_user.tuci_balance < tuci_cost:
        raise InsufficientFundsException()

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
            reference_id=body.listing_id,
            reference_type="listing",
        ))
        await db.commit()

    if free_used > 0:
        await credit_service.increment("blast", current_user.id, current_user.premium_since, count=free_used)

    logger.info("[Retargeting] Gönderildi | seller=%d | sent=%d | free=%d | paid=%d | cost=%d TUCi",
                current_user.id, sent, free_used, paid_count, tuci_cost)

    return {
        "sent": sent,
        "spent": tuci_cost,
        "message": f"{sent} kişiye geri hedefleme bildirimi gönderildi.",
    }


# ── Mass Notification Report & Click Tracking ──────────────────────────────────

@router.get("/mass-notification-report")
async def get_mass_notification_report(
    listing_id: int | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from sqlalchemy import select, func
    from app.models.mass_notification import MassNotificationCampaign
    from app.models.listing import Listing

    base = [MassNotificationCampaign.user_id == current_user.id]
    if listing_id:
        base.append(MassNotificationCampaign.listing_id == listing_id)

    agg = select(
        func.sum(MassNotificationCampaign.target_count).label('total_target'),
        func.sum(MassNotificationCampaign.sent_count).label('total_sent'),
        func.sum(MassNotificationCampaign.click_count).label('total_clicks'),
        func.sum(MassNotificationCampaign.spent_tuci).label('total_spent_tuci'),
        func.sum(MassNotificationCampaign.spent_free_credits).label('total_free_credits'),
    ).where(*base)

    row = (await db.execute(agg)).fetchone()

    response: dict = {
        "total_target": int(row.total_target or 0),
        "total_sent": int(row.total_sent or 0),
        "total_clicks": int(row.total_clicks or 0),
        "total_spent_tuci": int(row.total_spent_tuci or 0),
        "total_free_credits": int(row.total_free_credits or 0),
    }

    if listing_id:
        camp_q = (
            select(
                MassNotificationCampaign.id,
                MassNotificationCampaign.target_count,
                MassNotificationCampaign.sent_count,
                MassNotificationCampaign.click_count,
                MassNotificationCampaign.spent_tuci,
                MassNotificationCampaign.spent_free_credits,
                MassNotificationCampaign.created_at,
            )
            .where(*base)
            .order_by(MassNotificationCampaign.created_at.desc())
            .limit(30)
        )
        camps = (await db.execute(camp_q)).fetchall()
        response["campaigns"] = [
            {
                "id": r.id,
                "target_count": r.target_count,
                "sent_count": r.sent_count,
                "click_count": r.click_count,
                "spent_tuci": r.spent_tuci,
                "spent_free_credits": r.spent_free_credits,
                "sent_at": r.created_at.isoformat(),
            }
            for r in camps
        ]
        title_r = await db.execute(select(Listing.title).where(Listing.id == listing_id))
        response["listing_title"] = title_r.scalar()

    return response

@router.post("/campaign/{campaign_id}/click", status_code=204)
async def track_campaign_click(
    campaign_id: int,
    db: AsyncSession = Depends(get_db),
    # Optional auth if we track anon clicks
):
    from sqlalchemy import update
    from app.models.mass_notification import MassNotificationCampaign
    
    await db.execute(
        update(MassNotificationCampaign)
        .where(MassNotificationCampaign.id == campaign_id)
        .values(click_count=MassNotificationCampaign.click_count + 1)
    )
    await db.commit()
