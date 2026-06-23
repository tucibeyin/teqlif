"""
Mevcut tüm ilanlar için embedding backfill.

VPS'te bir kez çalıştır:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python -m scripts.backfill_embeddings

Sadece embedding=NULL olan ilanları işler (idempotent).
Batch'ler arasında kısa bekleme: model CPU'yu aşırı yüklemez.
"""

import asyncio
import time
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, update as sa_update
from app.database import AsyncSessionLocal
from app.models.listing import Listing
from app.services.ml_service import generate_embedding

BATCH_SIZE = 20
SLEEP_BETWEEN_BATCHES = 1.0  # saniye


async def run():
    print("[Backfill] Başlıyor...")
    total = 0
    offset = 0

    while True:
        async with AsyncSessionLocal() as db:
            rows = (await db.scalars(
                select(Listing)
                .where(Listing.embedding.is_(None), Listing.is_deleted.is_(False))
                .order_by(Listing.id)
                .limit(BATCH_SIZE)
                .offset(offset)
            )).all()

        if not rows:
            break

        for listing in rows:
            parts = [listing.title or ""]
            if listing.description:
                parts.append(listing.description)
            if listing.category:
                parts.append(listing.category)
            text = " ".join(parts).strip()

            try:
                embedding = generate_embedding(text)
                async with AsyncSessionLocal() as db:
                    await db.execute(
                        sa_update(Listing)
                        .where(Listing.id == listing.id)
                        .values(embedding=embedding)
                    )
                    await db.commit()
                total += 1
                print(f"  ✓ listing_id={listing.id} | '{listing.title[:40]}'")
            except Exception as exc:
                print(f"  ✗ listing_id={listing.id} HATA: {exc}")

        offset += BATCH_SIZE
        time.sleep(SLEEP_BETWEEN_BATCHES)

    print(f"\n[Backfill] Tamamlandı. Toplam işlenen: {total} ilan.")


if __name__ == "__main__":
    asyncio.run(run())
