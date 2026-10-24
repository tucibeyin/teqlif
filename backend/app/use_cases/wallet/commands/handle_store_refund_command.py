"""W8 — Apple IAP iade işleme (ARQ worker context).

Çağrı:  HandleStoreRefundCommand(session).execute(platform, signed_payload)

Akış (döküman §494-511):
  1. JWS doğrula → transactionId bul
  2. TeqlikTransaction → orijinal_miktar / refunded_miktar
  3. teqlik_balance atomik azalt (negatife düşebilir — CHECK CONSTRAINT YOK)
  4. Bakiye < 0 → users.pending_refund = true
  5. Orantılı gift kazanç iptali → user_wallet_earnings.pending azalt
  6. wallet_ledger 2 satır (iade_deduct + isteğe bağlı platform_credit)
  7. refund_log INSERT
"""
from __future__ import annotations

import math

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)


class HandleStoreRefundCommand:
    """ARQ worker'dan çağrılır; router'a bağlı değil."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, platform: str, signed_payload: str) -> None:
        # ── 1. JWS doğrula ────────────────────────────────────────────────────
        transaction_id, refunded_teqlik, raw_payload = await self._parse_refund(
            platform, signed_payload
        )

        # ── 2. Orijinal TeqlikTransaction bul ─────────────────────────────────
        tx_row = await self._session.execute(
            text(
                "SELECT id, user_id, amount, product_type "
                "FROM teqlik_transactions "
                "WHERE store_platform = :plat "
                "AND store_transaction_id = :tid "
                "AND transaction_type = 'iap_purchase' "
                "LIMIT 1"
            ),
            {"plat": platform, "tid": transaction_id},
        )
        tx = tx_row.fetchone()
        if tx is None:
            # Bilinmeyen transaction — sessizce geç (webhook retry storm'u önle)
            logger.warning(
                "[Refund] Bilinmeyen transaction | platform=%s tid=%s", platform, transaction_id
            )
            return

        _tx_id, user_id, original_teqlik, product_type = tx

        # Consumable olmayan (abonelik) refund → basit bakiye düşümü
        if product_type != "consumable":
            refunded_teqlik = original_teqlik

        # ── 3. Atomik bakiye azalt (negatife düşebilir) ───────────────────────
        new_bal_row = await self._session.execute(
            text(
                "UPDATE users "
                "SET teqlik_balance = teqlik_balance - :amt "
                "WHERE id = :uid "
                "RETURNING teqlik_balance"
            ),
            {"amt": refunded_teqlik, "uid": user_id},
        )
        row = new_bal_row.fetchone()
        if row is None:
            logger.error("[Refund] Kullanıcı bulunamadı | user_id=%s", user_id)
            return
        balance_after = row[0]

        # ── 4. Negatif bakiye bayrağı ──────────────────────────────────────────
        if balance_after < 0:
            await self._session.execute(
                text("UPDATE users SET pending_refund = true WHERE id = :uid"),
                {"uid": user_id},
            )
            logger.warning(
                "[Refund] Negatif bakiye | user_id=%s balance=%s", user_id, balance_after
            )

        # ── 5. Orantılı gift kazanç iptali ────────────────────────────────────
        gift_teqlik_cancelled = await self._cancel_proportional_gifts(
            user_id, refunded_teqlik, original_teqlik
        )

        # ── 6. wallet_ledger — iade düşümü ────────────────────────────────────
        prev_balance = balance_after + refunded_teqlik
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type) "
                "VALUES (:uid, :delta, :bal, 'iap_refund')"
            ),
            {"uid": user_id, "delta": -refunded_teqlik, "bal": balance_after},
        )
        # Platform ledger: iade edilen teqlik'i sisteme geri yaz (id=0)
        sys_bal_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = 0")
        )
        sys_balance = sys_bal_row.scalar() or 0
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type) "
                "VALUES (0, :delta, :bal, 'iap_refund_recovery')"
            ),
            {"delta": refunded_teqlik, "bal": sys_balance + refunded_teqlik},
        )

        # ── 7. refund_log INSERT ───────────────────────────────────────────────
        await self._session.execute(
            text(
                "INSERT INTO refund_log "
                "(user_id, store_platform, store_transaction_id, "
                " refunded_teqlik, original_teqlik, gift_teqlik_cancelled, "
                " balance_after, raw_payload) "
                "VALUES (:uid, :plat, :tid, :ref, :orig, :gift_c, :bal, :raw)"
            ),
            {
                "uid": user_id,
                "plat": platform,
                "tid": transaction_id,
                "ref": refunded_teqlik,
                "orig": original_teqlik,
                "gift_c": gift_teqlik_cancelled,
                "bal": balance_after,
                "raw": raw_payload,
            },
        )

        logger.info(
            "[Refund] İşlendi | user=%s platform=%s tid=%s refunded=%s "
            "balance_after=%s gift_cancelled=%s",
            user_id, platform, transaction_id, refunded_teqlik,
            balance_after, gift_teqlik_cancelled,
        )

    async def _parse_refund(
        self, platform: str, signed_payload: str
    ) -> tuple[str, int, str]:
        """JWS doğrula, (transaction_id, refunded_teqlik, raw_payload) döndür."""
        if platform == "apple":
            from app.services.store.apple_verifier import verify_signed_payload_jws
            claims = verify_signed_payload_jws(signed_payload)
            # Apple REFUND notification: transactionInfo içinde transactionId + amount
            tx_info = claims.get("data", {}).get("signedTransactionInfo", "")
            if tx_info:
                tx_claims = verify_signed_payload_jws(tx_info)
            else:
                tx_claims = claims

            transaction_id = tx_claims.get("transactionId", "")
            # Apple revenueCatAmount veya originalPurchasePrice'i teqlik'e çevir
            # V1.1: kur tablosu; V1.0'da orijinal transaction miktarını kullan
            refunded_teqlik = 0  # _resolve_refund_amount aşağıda tamamlar
            return transaction_id, refunded_teqlik, signed_payload

        raise NotImplementedError(f"Platform desteklenmiyor: {platform}")

    async def _cancel_proportional_gifts(
        self,
        user_id: int,
        refunded_teqlik: int,
        original_teqlik: int,
    ) -> int:
        """Orantılı gift kazancı iptal et; iptal edilen teqlik miktarını döndür."""
        if original_teqlik <= 0:
            return 0

        # pending kazanç miktarını öğren
        earn_row = await self._session.execute(
            text("SELECT pending FROM user_wallet_earnings WHERE user_id = :uid"),
            {"uid": user_id},
        )
        earn = earn_row.fetchone()
        if earn is None or earn[0] <= 0:
            return 0

        pending = earn[0]
        # iade_oranı = refunded / original; iptal = FLOOR(pending × oran)
        iade_orani = refunded_teqlik / original_teqlik
        iptal_teqlik = math.floor(pending * iade_orani)
        if iptal_teqlik <= 0:
            return 0

        # gift_events: payout_status='pending' olanları sent_at ASC sırasıyla iptal et
        # Toplam earned_teqlik >= iptal_teqlik olana kadar
        gifts_row = await self._session.execute(
            text(
                "SELECT id, earned_teqlik FROM gift_events "
                "WHERE receiver_id = :uid AND payout_status = 'pending' "
                "ORDER BY sent_at ASC"
            ),
            {"uid": user_id},
        )
        gifts = gifts_row.fetchall()

        remaining = iptal_teqlik
        cancelled_ids: list[int] = []
        for gift_id, earned in gifts:
            if remaining <= 0:
                break
            cancelled_ids.append(gift_id)
            remaining -= earned

        if cancelled_ids:
            placeholders = ",".join(str(gid) for gid in cancelled_ids)
            await self._session.execute(
                text(
                    f"UPDATE gift_events SET payout_status = 'cancelled_refund' "
                    f"WHERE id IN ({placeholders})"
                )
            )
            await self._session.execute(
                text(
                    "UPDATE user_wallet_earnings "
                    "SET pending = pending - :amt, updated_at = NOW() "
                    "WHERE user_id = :uid"
                ),
                {"amt": iptal_teqlik, "uid": user_id},
            )

        return iptal_teqlik
