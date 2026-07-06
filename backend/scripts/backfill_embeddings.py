"""
Geçmiş ilan embeddings backfill scripti.

Kullanım (VPS'te):
    cd /var/www/teqlif.com/backend
    source /var/www/teqlif.com/venv/bin/activate
    python backfill_embeddings.py

Özellikler:
  - embedding IS NULL olan aktif ilanları 50'şerli batch ile işler
  - Her batch'te `WHERE embedding IS NULL LIMIT 50` sorgular (offset yok,
    güncellenen kayıtlar bir sonraki batch'e dahil olmaz)
  - Her batch sonunda commit eder
  - Hata olan ilanlara NULL bırakır, devam eder
  - İdempotent: tekrar çalıştırılabilir
"""

import asyncio
import sys
import os
import time
import logging

# Backend modüllerini path'e ekle
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import select, update as sa_update, func

# Tüm modeller import edilmeli — SQLAlchemy relationship çözümü için
import app.models.like
import app.models.user
import app.models.auction
import app.models.bid
import app.models.block
import app.models.category
import app.models.favorite
import app.models.follow
import app.models.listing_impression
import app.models.listing_offer
import app.models.message
import app.models.notification
import app.models.purchase
import app.models.rating
import app.models.report
import app.models.story
import app.models.stream
import app.models.user_interest
import app.models.analytics

from app.database import AsyncSessionLocal
from app.models.listing import Listing
from app.services.ml_service import generate_embedding

# ── Loglama ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("backfill")

BATCH_SIZE = 50


# ── Yardımcı ───────────────────────────────────────────────────────────────────

def _build_text(listing: Listing) -> str:
    parts = [listing.title or ""]
    if listing.category:
        parts.append(listing.category)
    if listing.description:
        parts.append(listing.description)
    return " ".join(p.strip() for p in parts if p.strip())


# ── Ana mantık ─────────────────────────────────────────────────────────────────

async def _count_remaining(session) -> int:
    result = await session.scalar(
        select(func.count()).select_from(Listing).where(
            Listing.embedding.is_(None),
            Listing.is_deleted.is_(False),
        )
    )
    return result or 0


async def run() -> None:
    log.info("=" * 60)
    log.info("Backfill başlıyor...")

    async with AsyncSessionLocal() as session:
        total_remaining = await _count_remaining(session)

    if total_remaining == 0:
        log.info("Tüm aktif ilanların embedding değeri zaten dolu. Çıkılıyor.")
        return

    log.info(f"Toplam işlenecek ilan: {total_remaining}")
    log.info("=" * 60)

    processed_total = 0
    batch_no = 0
    t_start = time.monotonic()

    while True:
        async with AsyncSessionLocal() as session:
            # Her döngüde taze sorgu — offset yok, güncellenenler düşer
            rows = (
                await session.scalars(
                    select(Listing)
                    .where(
                        Listing.embedding.is_(None),
                        Listing.is_deleted.is_(False),
                    )
                    .order_by(Listing.id)
                    .limit(BATCH_SIZE)
                )
            ).all()

            if not rows:
                break

            batch_no += 1
            batch_ok = 0
            batch_fail = 0

            for listing in rows:
                text = _build_text(listing)
                if not text:
                    log.warning(f"  [ATLA] id={listing.id} — metin boş")
                    batch_fail += 1
                    continue
                try:
                    embedding = generate_embedding(text)
                    await session.execute(
                        sa_update(Listing)
                        .where(Listing.id == listing.id)
                        .values(embedding=embedding)
                    )
                    batch_ok += 1
                except Exception as exc:
                    log.error(f"  [HATA] id={listing.id}: {exc}")
                    batch_fail += 1

            await session.commit()

            processed_total += batch_ok
            remaining = await _count_remaining(session)
            elapsed = time.monotonic() - t_start
            speed = processed_total / elapsed if elapsed > 0 else 0
            eta_sec = int(remaining / speed) if speed > 0 else 0

            log.info(
                f"Batch #{batch_no:>3} tamamlandı — "
                f"bu batch: {batch_ok} başarılı / {batch_fail} hatalı | "
                f"toplam işlenen: {processed_total} | "
                f"kalan: {remaining} | "
                f"hız: {speed:.1f} ilan/sn | "
                f"tahmini kalan süre: {eta_sec // 60}dk {eta_sec % 60}sn"
            )

    elapsed_total = time.monotonic() - t_start
    log.info("=" * 60)
    log.info(
        f"Backfill tamamlandı. "
        f"Toplam işlenen: {processed_total} ilan | "
        f"Süre: {int(elapsed_total // 60)}dk {int(elapsed_total % 60)}sn"
    )


if __name__ == "__main__":
    asyncio.run(run())
