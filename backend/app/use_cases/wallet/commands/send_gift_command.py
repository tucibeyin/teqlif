from __future__ import annotations
import math
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, InsufficientFundsException, NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)

# gift_name → maliyet (teqlik); 8 katman
GIFT_COSTS: dict[str, int] = {
    "clap":          1,
    "tea":           5,
    "fire":          10,
    "diamond":       50,
    "crown":         100,
    "golden_hammer": 250,
    "rocket":        500,
    "trophy":        1000,
}

_HOST_SHARE_PRO = 95   # %95
_HOST_SHARE_STD = 70   # %70


class SendGiftCommand:
    """Hediye gönderme — wallet_ledger 3 satır, post-commit domain events."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(
        self,
        sender_id: int,
        receiver_username: str,
        gift_name: str,
        stream_id: int,
    ) -> dict:
        # ── Doğrulama ──────────────────────────────────────────────────────────
        cost = GIFT_COSTS.get(gift_name)
        if cost is None:
            raise BadRequestException(code="INVALID_GIFT_NAME")

        # ── Redis Token Bucket — 2/sn per sender (Fail-Safe) ──────────────────
        await self._check_rate_limit(sender_id)

        # ── Alıcıyı bul ────────────────────────────────────────────────────────
        receiver_row = await self._session.execute(
            text(
                "SELECT id, user_type FROM users "
                "WHERE username = :uname AND status = 'active' LIMIT 1"
            ),
            {"uname": receiver_username},
        )
        receiver = receiver_row.fetchone()
        if receiver is None:
            raise NotFoundException(code="RECEIVER_NOT_FOUND")

        receiver_id, receiver_type = receiver
        if receiver_id == sender_id:
            raise BadRequestException(code="SELF_GIFT_FORBIDDEN")

        # ── Kazanç hesabı ──────────────────────────────────────────────────────
        host_share_pct = _HOST_SHARE_PRO if receiver_type == "pro" else _HOST_SHARE_STD
        earned_teqlik   = math.floor(cost * host_share_pct / 100)  # INTEGER
        platform_teqlik = cost - earned_teqlik

        # ── Deterministik kilit sırası (deadlock önleme) ───────────────────────
        # LEAST(sender, host) önce kilitlenir; aynı sıra her zaman aynı yönde.
        first_id  = min(sender_id, receiver_id)
        second_id = max(sender_id, receiver_id)

        await self._session.execute(
            text("SELECT id FROM users WHERE id = :id FOR UPDATE"),
            {"id": first_id},
        )
        await self._session.execute(
            text("SELECT id FROM users WHERE id = :id FOR UPDATE"),
            {"id": second_id},
        )

        # ── Atomik bakiye düşümü (sender) ──────────────────────────────────────
        deduct = await self._session.execute(
            text(
                "UPDATE users SET teqlik_balance = teqlik_balance - :cost "
                "WHERE id = :uid AND teqlik_balance >= :cost "
                "RETURNING teqlik_balance"
            ),
            {"cost": cost, "uid": sender_id},
        )
        row = deduct.fetchone()
        if row is None:
            raise InsufficientFundsException()
        sender_balance_after = row[0]

        # ── user_wallet_earnings.pending artırımı (alıcı) ─────────────────────
        # INSERT ... ON CONFLICT — ilk hediye için satır yoksa oluştur.
        await self._session.execute(
            text(
                "INSERT INTO user_wallet_earnings (user_id, pending, available) "
                "VALUES (:uid, :earn, 0) "
                "ON CONFLICT (user_id) DO UPDATE "
                "SET pending = user_wallet_earnings.pending + :earn, "
                "    updated_at = NOW()"
            ),
            {"uid": receiver_id, "earn": earned_teqlik},
        )

        # ── gift_events kaydı ──────────────────────────────────────────────────
        gift_row = await self._session.execute(
            text(
                "INSERT INTO gift_events "
                "(stream_id, sender_id, receiver_id, gift_name, cost_teqlik, "
                " host_share, earned_teqlik, host_share_pct, payout_status) "
                "VALUES (:stream_id, :sender_id, :receiver_id, :gift_name, :cost, "
                "        :host_share_int, :earned, :pct, 'pending') "
                "RETURNING id"
            ),
            {
                "stream_id": stream_id,
                "sender_id": sender_id,
                "receiver_id": receiver_id,
                "gift_name": gift_name,
                "cost": cost,
                "host_share_int": earned_teqlik,  # eski kolon uyumu
                "earned": earned_teqlik,
                "pct": float(host_share_pct),
            },
        )
        gift_event_id = gift_row.fetchone()[0]

        # ── wallet_ledger — 3 satır (çift taraflı defter) ─────────────────────
        # 1. Gönderen: -cost
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, :delta, :bal, 'gift_sent', :ref_id, 'gift_event')"
            ),
            {
                "uid": sender_id,
                "delta": -cost,
                "bal": sender_balance_after,
                "ref_id": gift_event_id,
            },
        )

        # 2. Alıcı: +earned_teqlik — balance_after gerçek teqlik_balance değil;
        #    earned_teqlik user_wallet_earnings.pending'e gider, wallet_ledger'da
        #    earned_teqlik kümülatif toplamı tracking için kullanılır.
        receiver_bal_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = :uid"),
            {"uid": receiver_id},
        )
        receiver_balance = receiver_bal_row.scalar() or 0
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, :delta, :bal, 'gift_earned', :ref_id, 'gift_event')"
            ),
            {
                "uid": receiver_id,
                "delta": earned_teqlik,
                "bal": receiver_balance,  # teqlik_balance sabit; pending değişti
                "ref_id": gift_event_id,
            },
        )

        # 3. Sistem (id=0): +platform_teqlik
        sys_bal_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = 0")
        )
        sys_balance = sys_bal_row.scalar() or 0
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (0, :delta, :bal, 'platform_revenue', :ref_id, 'gift_event')"
            ),
            {
                "delta": platform_teqlik,
                "bal": sys_balance + platform_teqlik,
                "ref_id": gift_event_id,
            },
        )

        # ── teqlik_transactions (sender) ───────────────────────────────────────
        await self._session.execute(
            text(
                "INSERT INTO teqlik_transactions "
                "(user_id, amount, transaction_type, reference_id, reference_type) "
                "VALUES (:uid, :amt, 'send_gift', :ref_id, 'gift_event')"
            ),
            {"uid": sender_id, "amt": -cost, "ref_id": gift_event_id},
        )

        logger.info(
            "[SendGift] Başarılı | sender=%s receiver=%s gift=%s cost=%s earned=%s platform=%s",
            sender_id, receiver_id, gift_name, cost, earned_teqlik, platform_teqlik,
        )

        return {
            "gift_event_id": gift_event_id,
            "gift_name": gift_name,
            "cost": cost,
            "earned_teqlik": earned_teqlik,
            "platform_teqlik": platform_teqlik,
            "host_share_pct": host_share_pct,
            "receiver_id": receiver_id,
            "stream_id": stream_id,
        }

    async def _check_rate_limit(self, sender_id: int) -> None:
        """Redis Token Bucket 2/sn — Fail-Safe (Redis çökerse DB atomik kontrole düşer)."""
        try:
            from app.utils.redis_client import get_redis
            redis = await get_redis()
            key = f"rate:gift:{sender_id}"
            count = await redis.incr(key)
            if count == 1:
                await redis.expire(key, 1)
            if count > 2:
                from app.core.exceptions import TooManyRequestsException
                raise TooManyRequestsException(code="GIFT_RATE_LIMIT")
        except Exception as exc:
            # TooManyRequestsException'ı yeniden fırlat
            from app.core.exceptions import TooManyRequestsException
            if isinstance(exc, TooManyRequestsException):
                raise
            # Redis bağlantı hatası → Fail-Safe: DB atomik kontrole devam
            logger.warning("[SendGift] Redis rate limit kontrolü atlandı | %s", exc)
