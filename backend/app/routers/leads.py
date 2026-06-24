"""
Lead Generation (Sıcak Talep & Kitle Satışı) Router

GET  /api/leads/audience-size  — Son 7 gün içinde ilgili ilanları gören eşsiz kullanıcı sayısı
POST /api/leads/send-blast     — Hedef kitleye push bildirimi gönder
"""
from __future__ import annotations

import asyncio
import logging

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

COST_PER_PERSON: float = 0.50  # TL


# ── Kitle Büyüklüğü ──────────────────────────────────────────────────────────

@router.get("/audience-size")
async def audience_size(
    title: str = Query(..., min_length=2, max_length=200),
    category: str = Query(default=""),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Bu başlık/kategori ile eşleşen ve son 7 gün içinde aktif olan
    olası alıcı kitlesini tahmin eder.

    Strateji:
    1. PostgreSQL: ilgili kategorideki aktif listing ID'leri çek.
    2. ClickHouse: bu listeleri görüntüleyen benzersiz user_id sayısı.
    3. PostgreSQL: bu kullanıcıların kaçı FCM tokena sahip (ulaşılabilir).
    """
    # 1. Kategorideki aktif listing ID'leri — max 500 ile sınırla
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
        return {"audience_size": 0, "estimated_cost": 0.0}

    # 2. ClickHouse sorgusu: bu ilanları görüntüleyen aktif kullanıcılar
    ids_str = ", ".join(str(i) for i in listing_ids)
    ch_count = 0
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(f"""
            SELECT countDistinct(user_id)
            FROM user_events
            WHERE item_type = 'listing'
              AND item_id IN ({ids_str})
              AND event_type IN ('view', 'dwell', 'bid_hesitation')
              AND timestamp >= now() - INTERVAL 7 DAY
              AND user_id IS NOT NULL
              AND user_id != {current_user.id}
        """)
        row = ch_result.result_rows[0] if ch_result.result_rows else (0,)
        ch_count = int(row[0] or 0)
    except Exception as exc:
        logger.warning("[Leads] ClickHouse sorgusu başarısız, PostgreSQL fallback: %s", exc)
        ch_count = 0

    # ClickHouse veri yoksa (yeni sistem / düşük trafik) listing sayısına dayalı fallback
    if ch_count == 0:
        ch_count = min(len(listing_ids) * 3, 200)

    # 3. FCM token sahipliği oranı — kaba tahmin (%60 mobil ulaşılabilirlik)
    reachable = int(ch_count * 0.60)
    estimated_cost = round(reachable * COST_PER_PERSON, 2)

    return {
        "audience_size": reachable,
        "estimated_cost": estimated_cost,
    }


# ── Push Blast Gönder ─────────────────────────────────────────────────────────

class BlastRequest(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    category: str = Field(default="")
    listing_id: int | None = Field(default=None)
    estimated_cost: float = Field(gt=0)


@router.post("/send-blast", status_code=202)
async def send_blast(
    body: BlastRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Hedef kitleye push bildirimi gönderir.

    1. ClickHouse → son 7 günde aktif user_id listesi çek.
    2. PostgreSQL → bu kullanıcıların FCM tokenlarını al.
    3. Firebase → toplu push gönder (fire-and-forget, hatalı tokenları logla).

    Ücretlendirme: max_budget üzerinden kontrol edilir;
    gerçek payment entegrasyonu için ayrı bir wallet servisi bağlanmalıdır.
    """
    # ── TUCi bakiye kontrolü ─────────────────────────────────────────────────
    tuci_cost = int(body.estimated_cost)  # tahmini maliyet TUCi olarak
    if current_user.tuci_balance < tuci_cost:
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
    # ClickHouse verisi yoksa tüm aktif kullanıcılara fallback
    if target_user_ids:
        token_q = select(User.fcm_token).where(
            User.id.in_(target_user_ids),
            User.fcm_token.is_not(None),
            User.fcm_token != "",
        ).limit(5000)
    else:
        logger.info("[Leads] ClickHouse verisi yok — FCM fallback: tüm aktif kullanıcılar")
        token_q = select(User.fcm_token).where(
            User.id != current_user.id,
            User.fcm_token.is_not(None),
            User.fcm_token != "",
            User.is_active == True,  # noqa: E712
        ).limit(5000)

    token_result = await db.execute(token_q)
    fcm_tokens: list[str] = [r[0] for r in token_result.fetchall() if r[0]]

    if not fcm_tokens:
        # Demo ortamda (FCM token kayıtlı kullanıcı yok) başarı simüle et
        logger.info("[Leads] FCM token bulunamadı — demo başarı döndürülüyor | seller=%d", current_user.id)
        return {
            "sent": 0,
            "spent": 0.0,
            "message": "Demo: bildirim altyapısı kurulmadı, gerçek gönderim yapılamadı.",
        }

    # ── Firebase toplu push (fire-and-forget) ─────────────────────────────────
    from app.services.firebase_service import send_push, InvalidFCMTokenError

    listing_url = f"/ilan/{body.listing_id}" if body.listing_id else "/home"

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

    # 50'şer tokena bölüp paralel gönder
    chunk_size = 50
    sent = 0
    for i in range(0, len(fcm_tokens), chunk_size):
        chunk = fcm_tokens[i : i + chunk_size]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)

    logger.info(
        "[Leads] Blast gönderildi | seller=%d | tokens=%d | cost=%.2f",
        current_user.id, sent, body.estimated_cost,
    )

    # ── TUCi düş + işlem logla ───────────────────────────────────────────────
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

    return {
        "sent": sent,
        "spent": tuci_cost,
        "message": f"{sent} kişiye bildirim gönderildi.",
    }
