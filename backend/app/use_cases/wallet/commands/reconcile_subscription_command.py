"""Subscription reconciliation — Apple Server API üzerinden DB'yi Apple ile senkronize eder.

Çağrıldığında:
  1. Kullanıcının store_subscription_id (originalTransactionId) DB'den alınır.
  2. Apple'ın /inApps/v1/subscriptions/{id} endpoint'i sorgulanır.
  3. Apple'dan gelen plan_type / pro_expires_at DB'dekinden farklıysa güncellenir.
  4. Değişim özeti döner.

store_subscription_id NULL ise needs_restore=True döner — Flutter "Restore Purchases" gösterir.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger
from app.services.store.apple_server_api import get_subscription_status

logger = get_logger(__name__)

_PLAN_TYPE: dict[str, str] = {
    "teqlif_pro_1m":  "monthly",
    "teqlif_pro_3m":  "quarterly",
    "teqlif_pro_6m":  "biannual",
    "teqlif_pro_12m": "annual",
}


class ReconcileSubscriptionCommand:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int) -> dict:
        # Kullanıcının mevcut subscription bilgisini al
        row = await self._session.execute(
            text(
                "SELECT user_type, plan_type, pro_expires_at, "
                "store_subscription_id, store_subscription_platform "
                "FROM users WHERE id = :uid"
            ),
            {"uid": user_id},
        )
        user = row.fetchone()
        if user is None:
            return {"changed": False, "error": "user_not_found"}

        user_type, plan_type, pro_expires_at, sub_id, platform = user

        # PRO değilse reconcile gerekmiyor
        if user_type != "pro":
            return {"changed": False, "is_pro": False}

        # store_subscription_id yoksa client-side restore gerekiyor
        if not sub_id or platform != "apple":
            return {
                "changed": False,
                "needs_restore": True,
                "plan_type": plan_type,
            }

        # Apple Server API'den güncel durumu çek
        apple_status = await get_subscription_status(sub_id)
        if apple_status is None:
            # API erişilemedi — mevcut DB durumunu döndür, hata verme
            return {
                "changed": False,
                "sync_unavailable": True,
                "plan_type": plan_type,
                "expires_at": pro_expires_at.isoformat() if pro_expires_at else None,
            }

        # Aktif olmayan aboneliği client-side reconcile etme — downgrade S2S notification'ın işi
        if not apple_status.is_active:
            logger.info(
                "[SubReconcile] Apple aktif değil (status=%s), reconcile atlandı | user=%s",
                apple_status.status, user_id,
            )
            return {
                "changed": False,
                "plan_type": plan_type,
                "expires_at": pro_expires_at.isoformat() if pro_expires_at else None,
            }

        apple_plan = _PLAN_TYPE.get(apple_status.product_id)
        if not apple_plan:
            logger.warning(
                "[SubReconcile] Bilinmeyen Apple productId | user=%s product=%s",
                user_id, apple_status.product_id,
            )
            return {"changed": False, "plan_type": plan_type}

        # Fark var mı?
        expires_changed = (
            apple_status.expires_at is not None
            and pro_expires_at is not None
            and abs((apple_status.expires_at - pro_expires_at.replace(tzinfo=timezone.utc)).total_seconds()) > 60
        ) or (apple_status.expires_at is not None and pro_expires_at is None)

        plan_changed = apple_plan != plan_type

        if not plan_changed and not expires_changed:
            return {
                "changed": False,
                "plan_type": plan_type,
                "expires_at": pro_expires_at.isoformat() if pro_expires_at else None,
            }

        # Güncelle
        await self._session.execute(
            text(
                "UPDATE users SET plan_type = :plan, pro_expires_at = :exp "
                "WHERE id = :uid"
            ),
            {
                "plan": apple_plan,
                "exp": apple_status.expires_at,
                "uid": user_id,
            },
        )

        logger.info(
            "[SubReconcile] Güncellendi | user=%s %s→%s expires=%s",
            user_id, plan_type, apple_plan,
            apple_status.expires_at.isoformat() if apple_status.expires_at else "?",
        )

        return {
            "changed": True,
            "plan_type": apple_plan,
            "expires_at": apple_status.expires_at.isoformat() if apple_status.expires_at else None,
            "previous_plan_type": plan_type,
        }
