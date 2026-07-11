"""
TuciTransaction reference_id / reference_type backfill scripti.

Hangi türler backfill edilir:
  spend_boost_paid  → ad_campaigns  (seller_id + created_at ±10s)
  spend_lead_gen    → mass_notification_campaigns  (user_id + created_at ±10s, listing_id öncelikli)
  spend_retargeting → mass_notification_campaigns  (user_id + created_at ±10s, listing_id öncelikli)

Hangi türler atlanır (eşleşecek tablo yok):
  spend_boost (PRO ücretsiz) — yeni kayıt, zaten reference_id ile oluşuyor
  spend_reactivation         — audit tablosu yok
  spend_ai                   — audit tablosu yok
  send_gift / receive_gift   — yeni kayıtlar zaten stream reference_id ile oluşuyor

Güvenlik kuralları:
  - Yalnızca reference_id IS NULL olan işlemleri günceller (idempotent)
  - Zaman penceresinde birden fazla eşleşme varsa GÜNCELLEME YAPILMAZ (ambiguous)
  - --dry-run ile gerçek write yapılmaz, sadece raporlar

Kullanım (VPS'te):
    cd /var/www/teqlif.com/backend
    source /var/www/teqlif.com/venv/bin/activate

    # Önce kuru çalıştır, ne yapacağını gör:
    python scripts/backfill_txn_references.py --dry-run

    # Sonuçlar iyiyse gerçekten çalıştır:
    python scripts/backfill_txn_references.py
"""

import asyncio
import os
import sys
import argparse
import logging
from datetime import timedelta

# Backend modüllerini path'e ekle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, update as sa_update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Uygulama config + modeller ───────────────────────────────────────────────

from app.config import settings  # gerçek DATABASE_URL buradan geliyor

import app.models.user
import app.models.listing
import app.models.ad_campaign
import app.models.mass_notification
import app.models.tuci_transaction

from app.models.tuci_transaction import TuciTransaction
from app.models.ad_campaign import AdCampaign
from app.models.mass_notification import MassNotificationCampaign

# Zaman eşiği: aynı DB transaction'ı içinde oluşturulduklarından 10s fazlasıyla yeterli
WINDOW_SECONDS = 10

# ── Yardımcı ────────────────────────────────────────────────────────────────

def _window(created_at):
    return (
        created_at - timedelta(seconds=WINDOW_SECONDS),
        created_at + timedelta(seconds=WINDOW_SECONDS),
    )


# ── Backfill mantığı ────────────────────────────────────────────────────────

async def backfill_boost(session: AsyncSession, dry_run: bool) -> dict:
    """spend_boost_paid → ad_campaigns (seller_id + created_at ±10s)"""
    stats = {"found": 0, "updated": 0, "ambiguous": 0, "no_match": 0}

    result = await session.execute(
        select(TuciTransaction).where(
            TuciTransaction.transaction_type == "spend_boost_paid",
            TuciTransaction.reference_id.is_(None),
        ).order_by(TuciTransaction.created_at)
    )
    txns = result.scalars().all()
    stats["found"] = len(txns)
    log.info(f"[boost] reference_id eksik işlem sayısı: {len(txns)}")

    for txn in txns:
        lo, hi = _window(txn.created_at)
        candidates = (await session.execute(
            select(AdCampaign).where(
                AdCampaign.seller_id == txn.user_id,
                AdCampaign.created_at >= lo,
                AdCampaign.created_at <= hi,
            )
        )).scalars().all()

        if len(candidates) == 0:
            stats["no_match"] += 1
            log.debug(f"  txn#{txn.id} @ {txn.created_at} → eşleşme yok")
        elif len(candidates) > 1:
            stats["ambiguous"] += 1
            ids = [c.id for c in candidates]
            log.warning(f"  txn#{txn.id} @ {txn.created_at} → belirsiz: ad_campaign#{ids}")
        else:
            camp = candidates[0]
            log.info(
                f"  txn#{txn.id} → listing_id={camp.listing_id}  "
                f"(campaign#{camp.id}, Δt={abs((txn.created_at - camp.created_at).total_seconds()):.1f}s)"
            )
            if not dry_run:
                await session.execute(
                    sa_update(TuciTransaction)
                    .where(TuciTransaction.id == txn.id)
                    .values(reference_id=camp.listing_id, reference_type="listing")
                )
            stats["updated"] += 1

    if not dry_run and stats["updated"] > 0:
        await session.commit()
        log.info(f"[boost] {stats['updated']} kayıt commit edildi.")

    return stats


async def backfill_mass_notifications(session: AsyncSession, dry_run: bool) -> dict:
    """spend_lead_gen + spend_retargeting → mass_notification_campaigns (user_id + created_at ±10s)"""
    stats = {"found": 0, "updated": 0, "ambiguous": 0, "no_match": 0}

    result = await session.execute(
        select(TuciTransaction).where(
            TuciTransaction.transaction_type.in_(["spend_lead_gen", "spend_retargeting"]),
            TuciTransaction.reference_id.is_(None),
        ).order_by(TuciTransaction.created_at)
    )
    txns = result.scalars().all()
    stats["found"] = len(txns)
    log.info(f"[notif] reference_id eksik işlem sayısı: {len(txns)}")

    for txn in txns:
        lo, hi = _window(txn.created_at)
        candidates = (await session.execute(
            select(MassNotificationCampaign).where(
                MassNotificationCampaign.user_id == txn.user_id,
                MassNotificationCampaign.created_at >= lo,
                MassNotificationCampaign.created_at <= hi,
            )
        )).scalars().all()

        if len(candidates) == 0:
            stats["no_match"] += 1
            log.debug(f"  txn#{txn.id} ({txn.transaction_type}) @ {txn.created_at} → eşleşme yok")
        elif len(candidates) > 1:
            stats["ambiguous"] += 1
            ids = [c.id for c in candidates]
            log.warning(
                f"  txn#{txn.id} ({txn.transaction_type}) @ {txn.created_at} → belirsiz: campaign#{ids}"
            )
        else:
            camp = candidates[0]
            # listing_id varsa onu kullan, yoksa stream_id
            if camp.listing_id is not None:
                ref_id, ref_type = camp.listing_id, "listing"
            elif camp.stream_id is not None:
                ref_id, ref_type = camp.stream_id, "stream"
            else:
                stats["no_match"] += 1
                log.warning(f"  txn#{txn.id} → campaign#{camp.id} hem listing_id hem stream_id null, atlandı")
                continue

            log.info(
                f"  txn#{txn.id} ({txn.transaction_type}) → {ref_type}_id={ref_id}  "
                f"(campaign#{camp.id}, Δt={abs((txn.created_at - camp.created_at).total_seconds()):.1f}s)"
            )
            if not dry_run:
                await session.execute(
                    sa_update(TuciTransaction)
                    .where(TuciTransaction.id == txn.id)
                    .values(reference_id=ref_id, reference_type=ref_type)
                )
            stats["updated"] += 1

    if not dry_run and stats["updated"] > 0:
        await session.commit()
        log.info(f"[notif] {stats['updated']} kayıt commit edildi.")

    return stats


# ── Ana fonksiyon ────────────────────────────────────────────────────────────

async def main(dry_run: bool):
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    mode = "DRY-RUN" if dry_run else "CANLI"
    log.info(f"══════════════════════════════════════════")
    log.info(f"  TuciTransaction reference backfill — {mode}")
    log.info(f"  Zaman penceresi: ±{WINDOW_SECONDS}s")
    log.info(f"══════════════════════════════════════════")

    async with async_session() as session:
        b = await backfill_boost(session, dry_run)
        n = await backfill_mass_notifications(session, dry_run)

    log.info("")
    log.info("── ÖZET ──────────────────────────────────")
    log.info(f"  spend_boost_paid   → bulunan:{b['found']}  güncellendi:{b['updated']}  belirsiz:{b['ambiguous']}  eşleşme yok:{b['no_match']}")
    log.info(f"  lead_gen+retarget  → bulunan:{n['found']}  güncellendi:{n['updated']}  belirsiz:{n['ambiguous']}  eşleşme yok:{n['no_match']}")
    log.info(f"  TOPLAM güncellendi : {b['updated'] + n['updated']}")
    if dry_run:
        log.info("")
        log.info("  ⚠  Dry-run modundaydı — hiçbir şey yazılmadı.")
        log.info("     Gerçek yazma için --dry-run bayrağı olmadan çalıştırın.")
    log.info("──────────────────────────────────────────")

    await engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TuciTransaction reference backfill")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Veritabanına yazmadan sadece raporla",
    )
    args = parser.parse_args()
    asyncio.run(main(dry_run=args.dry_run))
