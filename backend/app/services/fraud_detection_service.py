"""
Sahte teklif tespit servisi — shill bidding sinyal skoru hesaplama.

FraudDetectionService.evaluate_bid():
  - Teklif sahibinin IP'sini yayın sahibiyle karşılaştırır
  - Hesap yaşı ve doğrulama durumuna göre risk skoru hesaplar
  - Redis sayacı (shill_cnt) ile tekrarlayan sinyalleri izler
  - WARN → sayacı artırır, teklif geçer
  - MUTE → sistem otomatik susturma uygular, teklif bloke edilir
"""

import asyncio
import json
import time
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

# Shill bidding sinyal skorları
# IP eşleşmesi tek başına dominant olmamalı (aynı ağda meşru kullanıcılar olabilir)
_SHILL_SCORE_IP_MATCH     = 30  # IP eşleşmesi (tetikleyici, tek başına yeterli değil)
_SHILL_SCORE_UNVERIFIED   = 35  # Doğrulanmamış hesap + IP → ciddi sinyal
_SHILL_SCORE_NEW_ACCOUNT  = 25  # Hesap 7 günden genç
_SHILL_SCORE_REPEAT       = 10  # Aynı stream'de önceki sinyal başına (max 2x)
_SHILL_THRESHOLD_MUTE     = 80  # Verified+eski hesap aynı ağdan asla mute edilmez
_SHILL_THRESHOLD_WARN     = 45  # Bu skoru aşarsa: sayaç artır, teklif geçer
_SHILL_COUNTER_TTL        = 86_400  # Sinyal sayacı 24 saat canlı kalır


@dataclass
class FraudDecision:
    action: str  # "PASS" | "WARN" | "MUTE"
    score: int
    reason: str


async def _log_fraud_attempt(
    fraud_type: str,
    stream_id: int,
    user_id: int,
    username: str,
    extra: dict | None = None,
) -> None:
    """Dolandırıcılık girişimini logger + Redis fraud_log ZADD'e kaydeder."""
    payload = {
        "fraud_type": fraud_type,
        "stream_id": stream_id,
        "user_id": user_id,
        "username": username,
        **(extra or {}),
    }
    logger.warning(
        "[FRAUD_ATTEMPT] type=%s stream_id=%s user_id=%s username=%s extra=%s",
        fraud_type, stream_id, user_id, username, extra,
    )
    try:
        redis = await get_redis()
        score = time.time()
        value = json.dumps(payload)
        await redis.zadd("fraud_log", {value: score})
        cutoff = score - 30 * 24 * 3600
        await redis.zremrangebyscore("fraud_log", "-inf", cutoff)
    except Exception as exc:
        logger.error("[FRAUD_ATTEMPT] Redis log yazılamadı | %s", exc)


class FraudDetectionService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def evaluate_bid(
        self,
        stream_id: int,
        user: User,
        bidder_ip: str | None,
        host_ip: str | None,
        amount: float,
    ) -> FraudDecision:
        """
        Teklif sahibinin shill bidding riskini değerlendirir.

        Dönüş değeri:
          - PASS  → risk yok, teklif devam eder
          - WARN  → risk var ama eşiğin altında, sayaç artırılır, teklif devam eder
          - MUTE  → eşik aşıldı, system_mute uygulandı, teklif bloke edilmeli
        """
        from app.database_clickhouse import track_user_event

        # IP eşleşmesi yoksa doğrudan geç
        if not bidder_ip or not host_ip or bidder_ip != host_ip:
            return FraudDecision(action="PASS", score=0, reason="no_ip_match")

        shill_score = _SHILL_SCORE_IP_MATCH

        if not user.is_verified:
            shill_score += _SHILL_SCORE_UNVERIFIED

        created_at = user.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        account_age_days = (datetime.now(timezone.utc) - created_at).days
        if account_age_days < 7:
            shill_score += _SHILL_SCORE_NEW_ACCOUNT

        redis = await get_redis()
        shill_counter_key = f"shill_cnt:{stream_id}:{user.id}"
        prior_raw = await redis.get(shill_counter_key)
        prior_count = int(prior_raw) if prior_raw else 0
        shill_score += min(prior_count * _SHILL_SCORE_REPEAT, _SHILL_SCORE_REPEAT * 2)

        await _log_fraud_attempt(
            "shill_bidding",
            stream_id=stream_id,
            user_id=user.id,
            username=user.username,
            extra={"bidder_ip": bidder_ip, "amount": amount, "shill_score": shill_score},
        )

        if shill_score >= _SHILL_THRESHOLD_MUTE:
            from app.services.moderation_service import ModerationService
            await ModerationService(self.session).system_mute(
                stream_id, user.id, reason="shill_bidding"
            )
            asyncio.create_task(track_user_event(
                event_type="bid_fraud_mute",
                item_id=stream_id,
                item_type="stream",
                user_id=user.id,
                price_point=amount,
            ))
            return FraudDecision(action="MUTE", score=shill_score, reason="shill_bidding")

        if shill_score >= _SHILL_THRESHOLD_WARN:
            await redis.incr(shill_counter_key)
            await redis.expire(shill_counter_key, _SHILL_COUNTER_TTL)
            asyncio.create_task(track_user_event(
                event_type="bid_fraud_warn",
                item_id=stream_id,
                item_type="stream",
                user_id=user.id,
                price_point=amount,
            ))
            return FraudDecision(action="WARN", score=shill_score, reason="shill_bidding")

        return FraudDecision(action="PASS", score=shill_score, reason="shill_bidding_low_score")
