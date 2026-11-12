"""
Wallet Cron Görevleri

release_pending_earnings_task       — Her gün 02:15 (T+14 gift_events → available)
daily_financial_reconciliation_task — Her gün 00:00 (denetim raporu)
reset_monthly_withdrawal_quota_task — Her ayın 1'i 00:05 (V1.0: no-op)
check_expired_pro_users_task        — Her gün 03:10 (süresi dolmuş PRO güvenlik ağı)
process_store_notification_task     — ARQ enqueue (Apple/Google store notif işle)
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta

from sqlalchemy import text

from app.core.logger import get_logger, capture_exception, capture_message
from app.database import AsyncSessionLocal
from app.utils.telegram import send_telegram_alert

logger = get_logger(__name__)

_PENDING_HOLD_DAYS = 14


async def release_pending_earnings_task(ctx: dict) -> None:
    """T+14 dolmuş gift_events kazançlarını available'a taşı.

    gift_events.payout_status='pending' AND sent_at <= NOW()-14d
    → user_wallet_earnings: available += total, pending -= total
    → gift_events.payout_status = 'released'

    Tek CTE zinciriyle set-based SQL: kullanıcı başına N+1 döngü yok,
    transaction kısa tutulur, WAL şişmesi ve satır kilit birikimi önlenir.
    """
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(days=_PENDING_HOLD_DAYS)

        async with AsyncSessionLocal() as session:
            result = await session.execute(
                text("""
                    WITH amounts AS (
                        SELECT receiver_id,
                               SUM(earned_teqlik)::bigint AS total
                        FROM   gift_events
                        WHERE  payout_status = 'pending'
                          AND  sent_at <= :cutoff
                        GROUP  BY receiver_id
                        HAVING SUM(earned_teqlik) > 0
                    ),
                    wallet_update AS (
                        UPDATE user_wallet_earnings uwe
                        SET available  = uwe.available + a.total,
                            pending    = uwe.pending   - a.total,
                            updated_at = NOW()
                        FROM   amounts a
                        WHERE  uwe.user_id = a.receiver_id
                        RETURNING uwe.user_id,
                                  a.total        AS delta,
                                  uwe.available  AS balance_after
                    ),
                    ledger_insert AS (
                        INSERT INTO wallet_ledger
                               (user_id, delta_teqlik, balance_after,
                                tx_type, reference_type)
                        SELECT user_id, delta, balance_after,
                               'earnings_released', 'cron'
                        FROM   wallet_update
                        RETURNING user_id, delta_teqlik
                    ),
                    gift_update AS (
                        UPDATE gift_events
                        SET payout_status = 'released',
                            released_at   = NOW()
                        WHERE payout_status = 'pending'
                          AND sent_at <= :cutoff
                        RETURNING 1
                    )
                    SELECT
                        (SELECT COUNT(*)                            FROM ledger_insert) AS released_users,
                        (SELECT COALESCE(SUM(delta_teqlik), 0)     FROM ledger_insert) AS released_teqlik
                """),
                {"cutoff": cutoff},
            )
            row = result.fetchone()
            released_users  = int(row[0]) if row else 0
            released_teqlik = int(row[1]) if row else 0
            await session.commit()

        logger.info(
            "[WalletTask] release_pending_earnings: %d kullanıcı, %d teqlik serbest bırakıldı",
            released_users, released_teqlik,
        )
        await _agent_ok(ctx, "release_pending_earnings_task")

    except Exception as exc:
        logger.error("[WalletTask] release_pending_earnings başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def daily_financial_reconciliation_task(ctx: dict) -> None:
    """Günlük finansal denetim — 3 bağımsız muhasebe kovası:

    Kova 1 — pending tutarlılığı:
        SUM(user_wallet_earnings.pending) ↔ SUM(gift_events.earned_teqlik WHERE payout_status='pending')

    Kova 2 — withdrawal net (tüm zaman, pencere kayması yok):
        SUM(withdrawal_requests.teqlik_amount WHERE status NOT IN ('cancelled','rejected'))
        ↔ ABS(SUM(wallet_ledger.delta_teqlik WHERE tx_type IN
            ('withdrawal_request','withdrawal_cancelled','withdrawal_rejected')))

    Kova 3 — available tutarlılığı:
        SUM(user_wallet_earnings.available)
        ↔ SUM(earnings_released+withdrawal_request+withdrawal_cancelled+withdrawal_rejected deltas)
            − (SUM(convert_to_teqlik user delta) + SUM(bonus_mint system delta))
        [convert_net = convert_user_delta + bonus_mint_delta = teqlik_amount çekildi]

    Anomali varsa Telegram + Sentry error + _agent_fail; temizse _agent_ok.
    """
    anomalies = 0
    alert_lines: list[str] = []

    try:
        async with AsyncSessionLocal() as session:
            # 1. Negatif available/pending bakiye tespiti
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
                msg = (
                    f"Negatif bakiye: {len(neg_list)} kayıt | "
                    f"örnek: {[(r[0], int(r[1]), int(r[2])) for r in neg_list[:5]]}"
                )
                logger.warning("[Reconciliation] %s", msg)
                alert_lines.append(msg)

            # Kova 1 — pending ↔ gift_events (henüz serbest bırakılmamış kazançlar)
            pending_sum_row = await session.execute(
                text("SELECT COALESCE(SUM(pending), 0) FROM user_wallet_earnings")
            )
            pending_sum = int(pending_sum_row.fetchone()[0] or 0)

            gift_pending_row = await session.execute(
                text(
                    "SELECT COALESCE(SUM(earned_teqlik), 0) "
                    "FROM gift_events WHERE payout_status = 'pending'"
                )
            )
            gift_pending = int(gift_pending_row.fetchone()[0] or 0)

            if abs(pending_sum - gift_pending) > 0:
                anomalies += 1
                msg = (
                    f"Kova1 pending tutarsızlığı: "
                    f"wallet_pending={pending_sum} gift_pending={gift_pending} "
                    f"diff={abs(pending_sum - gift_pending)}"
                )
                logger.warning("[Reconciliation] %s", msg)
                alert_lines.append(msg)

            # Kova 2 — withdrawal net (tüm zaman — pencere kayması yok)
            # Net outstanding = pending + approved + completed taleplerin toplamı
            wr_net_row = await session.execute(
                text(
                    "SELECT COALESCE(SUM(teqlik_amount), 0) "
                    "FROM withdrawal_requests "
                    "WHERE status NOT IN ('cancelled', 'rejected')"
                )
            )
            wr_net = int(wr_net_row.fetchone()[0] or 0)

            # Ledger net: withdrawal_request (-), cancelled/rejected (+)
            # ABS toplamı = net outstanding teqlik
            ledger_withdrawal_row = await session.execute(
                text(
                    "SELECT ABS(COALESCE(SUM(delta_teqlik), 0)) "
                    "FROM wallet_ledger "
                    "WHERE tx_type IN ('withdrawal_request', 'withdrawal_cancelled', 'withdrawal_rejected')"
                )
            )
            ledger_withdrawal = int(ledger_withdrawal_row.fetchone()[0] or 0)

            if abs(wr_net - ledger_withdrawal) > 0:
                anomalies += 1
                msg = (
                    f"Kova2 withdrawal tutarsızlığı (tüm zaman): "
                    f"wr_net={wr_net} ledger_net={ledger_withdrawal} "
                    f"diff={abs(wr_net - ledger_withdrawal)}"
                )
                logger.warning("[Reconciliation] %s", msg)
                alert_lines.append(msg)

            # Kova 3 — available tutarlılığı
            # available = earnings_released net + withdrawal net
            #            − convert_net (convert_user + bonus_system = teqlik_amount çekildi)
            avail_sum_row = await session.execute(
                text("SELECT COALESCE(SUM(available), 0) FROM user_wallet_earnings")
            )
            avail_sum = int(avail_sum_row.fetchone()[0] or 0)

            earnings_withdrawal_net_row = await session.execute(
                text(
                    "SELECT COALESCE(SUM(delta_teqlik), 0) FROM wallet_ledger "
                    "WHERE tx_type IN ('earnings_released', 'withdrawal_request', "
                    "                  'withdrawal_cancelled', 'withdrawal_rejected')"
                )
            )
            earnings_withdrawal_net = int(earnings_withdrawal_net_row.fetchone()[0] or 0)

            # convert_net = SUM(convert_to_teqlik user) + SUM(bonus_mint system)
            # = (teqlik_amount + bonus) + (-bonus) = teqlik_amount = available'dan çekildi
            convert_net_row = await session.execute(
                text(
                    "SELECT "
                    "  COALESCE((SELECT SUM(delta_teqlik) FROM wallet_ledger "
                    "            WHERE tx_type = 'convert_to_teqlik' AND user_id != 0), 0) "
                    "+ COALESCE((SELECT SUM(delta_teqlik) FROM wallet_ledger "
                    "            WHERE tx_type = 'bonus_mint'), 0)"
                )
            )
            convert_net = int(convert_net_row.fetchone()[0] or 0)

            avail_ledger = earnings_withdrawal_net - convert_net

            if abs(avail_sum - avail_ledger) > 0:
                anomalies += 1
                msg = (
                    f"Kova3 available tutarsızlığı: "
                    f"wallet_available={avail_sum} ledger_net={avail_ledger} "
                    f"diff={abs(avail_sum - avail_ledger)}"
                )
                logger.warning("[Reconciliation] %s", msg)
                alert_lines.append(msg)

        if anomalies > 0:
            summary = (
                f"🚨 Finansal mutabakat anomalisi!\n"
                f"Anomali sayısı: {anomalies}\n"
                + "\n".join(f"• {line}" for line in alert_lines)
            )
            logger.error("[WalletTask] daily_financial_reconciliation | %s", summary)
            capture_message(
                f"[daily_financial_reconciliation] {summary}", level="error"
            )
            await send_telegram_alert(summary, rate_key="financial_reconciliation_anomaly")
            await _agent_fail(ctx, "daily_financial_reconciliation_task", f"anomalies={anomalies}")
        else:
            logger.info("[WalletTask] daily_financial_reconciliation tamamlandı | status=ok")
            await _agent_ok(ctx, "daily_financial_reconciliation_task")

    except Exception as exc:
        logger.error("[WalletTask] daily_financial_reconciliation başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        await _agent_fail(ctx, "daily_financial_reconciliation_task", str(exc))
        raise


async def reset_monthly_withdrawal_quota_task(ctx: dict) -> None:
    """Her ayın 1'inde aylık çekim sayacını sıfırla.

    V1.0: Aylık kota kolonu yok — no-op. V1.1'de eklenir.
    """
    try:
        logger.info("[WalletTask] reset_monthly_withdrawal_quota: V1.0 no-op")
        await _agent_ok(ctx, "reset_monthly_withdrawal_quota_task")

    except Exception as exc:
        logger.error("[WalletTask] reset_monthly_withdrawal_quota başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def check_expired_pro_users_task(ctx: dict) -> None:
    """pro_expires_at < NOW() olan kullanıcıları 'standard'a düşür (güvenlik ağı).

    Grace period (pro_grace_until) dolmadan düşürme yapılmaz.
    """
    downgraded = 0

    try:
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                text(
                    "UPDATE users "
                    "SET user_type = 'standard', plan_type = NULL, "
                    "    pro_expires_at = NULL, pro_grace_until = NULL "
                    "WHERE user_type = 'pro' "
                    "  AND pro_expires_at IS NOT NULL "
                    "  AND pro_expires_at < NOW() "
                    "  AND (pro_grace_until IS NULL OR pro_grace_until < NOW())"
                )
            )
            await session.commit()
            downgraded = result.rowcount

        if downgraded:
            logger.info("[WalletTask] check_expired_pro: %d kullanıcı standard'a düşürüldü", downgraded)
        else:
            logger.debug("[WalletTask] check_expired_pro: süresi dolan PRO yok")

        await _agent_ok(ctx, "check_expired_pro_users_task")

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
    """ARQ job — Apple/Google store bildirimini notificationType'a göre yönlendir."""
    try:
        async with AsyncSessionLocal() as session:
            if platform == "apple":
                from app.services.store.apple_verifier import verify_signed_payload_jws
                claims = verify_signed_payload_jws(signed_payload)
                notif_type = claims.get("notificationType", "")

                if notif_type == "REFUND":
                    # REFUND apple_handler.handle() üzerinden geçmez — UUID idempotency burada
                    notif_uuid = claims.get("notificationUUID")
                    if notif_uuid:
                        try:
                            from app.utils.redis_client import get_redis
                            _redis = await get_redis()
                            if not await _redis.set(
                                f"notif:apple:uuid:{notif_uuid}", "1", nx=True, ex=259200
                            ):
                                logger.info(
                                    "[StoreNotif] REFUND duplicate UUID atlandı | uuid=%s",
                                    notif_uuid,
                                )
                                return
                        except Exception as exc:
                            logger.warning(
                                "[StoreNotif] REFUND Redis idempotency check başarısız | %s", exc
                            )
                    from app.use_cases.wallet.commands.handle_store_refund_command import (
                        HandleStoreRefundCommand,
                    )
                    await HandleStoreRefundCommand(session).execute(
                        platform=platform, signed_payload=signed_payload
                    )
                else:
                    from app.services.store.notification_factory import StoreNotificationHandlerFactory
                    handler = StoreNotificationHandlerFactory.get(platform, session)
                    await handler.handle(signed_payload)
            elif platform == "google":
                from app.services.store.notification_factory import StoreNotificationHandlerFactory
                handler = StoreNotificationHandlerFactory.get("google", session)
                await handler.handle(signed_payload)
            else:
                logger.warning(
                    "[StoreNotif] Bilinmeyen platform, atlandı | platform=%s", platform
                )
                return

            await session.commit()

        logger.info("[StoreNotif] İşlendi | platform=%s", platform)

    except Exception as exc:
        logger.error(
            "[StoreNotif] process_store_notification başarısız | platform=%s | %s",
            platform, exc, exc_info=True,
        )
        capture_exception(exc)
        raise


async def _agent_ok(ctx: dict, job_name: str) -> None:
    """teqlif-agent watchdog'a 'job çalıştı' sinyali gönderir; önceki fail kaydını temizler."""
    try:
        await ctx["redis"].hset(
            "teqlif:agent:job_ok", job_name,
            datetime.now(timezone.utc).isoformat(),
        )
        await ctx["redis"].hdel("teqlif:agent:job_fail", job_name)
    except Exception:
        pass


async def _agent_fail(ctx: dict, job_name: str, reason: str = "") -> None:
    """teqlif-agent watchdog'a 'job başarısız' sinyali gönderir. job_ok yazılmaz."""
    try:
        await ctx["redis"].hset(
            "teqlif:agent:job_fail", job_name,
            f"{datetime.now(timezone.utc).isoformat()} | {reason}",
        )
    except Exception:
        pass
