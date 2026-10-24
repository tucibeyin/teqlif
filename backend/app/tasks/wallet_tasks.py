"""
Wallet Cron Görevleri

release_pending_earnings_task       — Her gün 02:15 (T+14 pending → available)
daily_financial_reconciliation_task — Her gün 00:00 (denetim raporu)
reset_monthly_withdrawal_quota_task — Her ayın 1'i 00:05 (aylık çekim kotası sıfırla)
check_expired_pro_users_task        — Her gün 03:10 (süresi dolmuş PRO güvenlik ağı)
process_store_notification_task     — ARQ enqueue (Apple/Google store notif işle)
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta

from sqlalchemy import text

from app.core.logger import get_logger, capture_exception
from app.database import AsyncSessionLocal

logger = get_logger(__name__)

_PENDING_HOLD_DAYS = 14  # T+14 kazanç kilit süresi


async def release_pending_earnings_task(ctx: dict) -> None:
    """T+14 dolmuş pending kazançları available'a taşı."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=_PENDING_HOLD_DAYS)
    released_users = 0
    released_teqlik = 0

    try:
        async with AsyncSessionLocal() as session:
            rows = await session.execute(
                text(
                    "SELECT user_id, SUM(pending_teqlik) AS amt "
                    "FROM user_wallet_earnings_pending "
                    "WHERE release_at <= :cutoff AND released = FALSE "
                    "GROUP BY user_id"
                ),
                {"cutoff": cutoff},
            )
            pending_rows = rows.fetchall()

            for user_id, amt in pending_rows:
                if not amt or amt <= 0:
                    continue

                await session.execute(
                    text(
                        "UPDATE user_wallet_earnings "
                        "SET available = available + :amt, updated_at = NOW() "
                        "WHERE user_id = :uid"
                    ),
                    {"amt": amt, "uid": user_id},
                )
                await session.execute(
                    text(
                        "UPDATE user_wallet_earnings_pending "
                        "SET released = TRUE, released_at = NOW() "
                        "WHERE user_id = :uid AND release_at <= :cutoff AND released = FALSE"
                    ),
                    {"uid": user_id, "cutoff": cutoff},
                )

                avail_row = await session.execute(
                    text("SELECT available FROM user_wallet_earnings WHERE user_id = :uid"),
                    {"uid": user_id},
                )
                avail_after = avail_row.fetchone()[0]

                await session.execute(
                    text(
                        "INSERT INTO wallet_ledger "
                        "(user_id, delta_teqlik, balance_after, tx_type, reference_type) "
                        "VALUES (:uid, :delta, :bal, 'earnings_released', 'cron')"
                    ),
                    {"uid": user_id, "delta": int(amt), "bal": int(avail_after)},
                )

                released_users += 1
                released_teqlik += int(amt)

            await session.commit()

        logger.info(
            "[WalletTask] release_pending_earnings: %d kullanıcı, %d teqlik serbest bırakıldı",
            released_users, released_teqlik,
        )

    except Exception as exc:
        logger.error("[WalletTask] release_pending_earnings başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def daily_financial_reconciliation_task(ctx: dict) -> None:
    """Günlük finansal denetim — wallet_ledger vs tablo bakiyeleri tutarlılık kontrolü."""
    anomalies = 0

    try:
        async with AsyncSessionLocal() as session:
            # Negatif available bakiye tespiti
            neg_rows = await session.execute(
                text(
                    "SELECT user_id, available, pending "
                    "FROM user_wallet_earnings "
                    "WHERE available < 0 OR pending < 0"
                )
            )
            neg_list = neg_rows.fetchall()
            if neg_list:
                anomalies += len(neg_list)
                logger.warning(
                    "[Reconciliation] Negatif bakiye tespit edildi: %d kayıt | %s",
                    len(neg_list),
                    [(r[0], r[1], r[2]) for r in neg_list[:10]],
                )

            # pending + approved + completed withdrawal toplamı vs ledger
            wr_row = await session.execute(
                text(
                    "SELECT COUNT(*), COALESCE(SUM(teqlik_amount), 0) "
                    "FROM withdrawal_requests "
                    "WHERE status IN ('pending', 'approved', 'completed') "
                    "AND created_at >= NOW() - INTERVAL '30 days'"
                )
            )
            wr_count, wr_total = wr_row.fetchone()

            ledger_row = await session.execute(
                text(
                    "SELECT COALESCE(SUM(ABS(delta_teqlik)), 0) "
                    "FROM wallet_ledger "
                    "WHERE tx_type IN ('withdrawal_request') "
                    "AND created_at >= NOW() - INTERVAL '30 days'"
                )
            )
            ledger_total = ledger_row.fetchone()[0]

            if wr_total and ledger_total and abs(int(wr_total) - int(ledger_total)) > 0:
                anomalies += 1
                logger.warning(
                    "[Reconciliation] withdrawal tutarsızlığı: wr_total=%s ledger_total=%s",
                    wr_total, ledger_total,
                )

        status = "ok" if anomalies == 0 else f"anomalies={anomalies}"
        logger.info("[WalletTask] daily_financial_reconciliation tamamlandı | status=%s", status)

    except Exception as exc:
        logger.error("[WalletTask] daily_financial_reconciliation başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def reset_monthly_withdrawal_quota_task(ctx: dict) -> None:
    """Her ayın 1'inde aylık çekim sayacını sıfırla."""
    try:
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                text(
                    "UPDATE user_wallet_earnings "
                    "SET monthly_withdrawal_count = 0, updated_at = NOW() "
                    "WHERE monthly_withdrawal_count > 0"
                )
            )
            await session.commit()
            updated = result.rowcount

        logger.info(
            "[WalletTask] reset_monthly_withdrawal_quota: %d kullanıcı sıfırlandı",
            updated,
        )

    except Exception as exc:
        logger.error("[WalletTask] reset_monthly_withdrawal_quota başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def check_expired_pro_users_task(ctx: dict) -> None:
    """pro_expires_at < NOW() olan kullanıcıları 'free'ye düşür (güvenlik ağı)."""
    downgraded = 0

    try:
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                text(
                    "UPDATE users "
                    "SET user_type = 'free', plan_type = NULL "
                    "WHERE user_type = 'pro' "
                    "AND pro_expires_at IS NOT NULL "
                    "AND pro_expires_at < NOW()"
                )
            )
            await session.commit()
            downgraded = result.rowcount

        if downgraded:
            logger.info("[WalletTask] check_expired_pro: %d kullanıcı free'ye düşürüldü", downgraded)
        else:
            logger.debug("[WalletTask] check_expired_pro: süresi dolan PRO yok")

    except Exception as exc:
        logger.error("[WalletTask] check_expired_pro başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def process_store_notification_task(
    ctx: dict,
    *,
    platform: str,
    signed_payload: str,
) -> None:
    """ARQ job — Apple/Google store bildirimini işle (JWS doğrulama + DB yazma)."""
    try:
        async with AsyncSessionLocal() as session:
            if platform == "apple":
                from app.use_cases.wallet.commands.handle_store_refund_command import (
                    HandleStoreRefundCommand,
                )
                cmd = HandleStoreRefundCommand(session)
                await cmd.execute(platform=platform, signed_payload=signed_payload)
            else:
                logger.warning(
                    "[StoreNotif] Bilinmeyen platform, atlandı | platform=%s", platform
                )
                return

        logger.info("[StoreNotif] İşlendi | platform=%s", platform)

    except Exception as exc:
        logger.error(
            "[StoreNotif] process_store_notification başarısız | platform=%s | %s",
            platform, exc, exc_info=True,
        )
        capture_exception(exc)
        raise
