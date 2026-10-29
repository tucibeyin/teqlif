"""
Teklif doğrulama servisi - Troll teklif koruması ve temel limitleri yönetir.
Clean Architecture gereği auction_commands içinden izole edilmiştir.
"""

from app.models.user import User
from app.core.exceptions import BadRequestException, ForbiddenException
from app.services.fraud_detection_service import _log_fraud_attempt
from app.database_clickhouse import track_user_event
import asyncio

# ── Mutlak tavan (doğrulanmış/doğrulanmamış ayrımı olmaksızın her kullanıcı için) ──
_ABSOLUTE_MAX_BID_TL  = 500_000.0   # platform teklif tavanı (TL)
_MAX_MULTIPLIER_HARD  = 15.0        # mevcut teklifin 15× üzeri → troll

# ── Telefon doğrulaması gerektiren eşikler ──
_HIGH_BID_THRESHOLD_TL          = 10_000
_HIGH_BID_THRESHOLD_UNVERIFIED  = 5_000

# Katlama kontrolü: mevcut teklif bu değerin üzerindeyken geçerli
_MULTIPLIER_MIN_BASE_TL = 500

# Mevcut fiyatın kaç katını aşarsa yüksek teklif sayılır
_HIGH_BID_MULTIPLIER            = 10   # verified
_HIGH_BID_MULTIPLIER_UNVERIFIED = 7    # unverified


class BidValidationService:
    @staticmethod
    async def validate_troll_bid(
        stream_id: int,
        user: User,
        data_amount: float,
        current_bid: float,
    ) -> None:
        """
        Teklifi iki katmanda doğrular:

        1. Hard ceiling (herkese uygulanır, telefon doğrulaması bypass etmez):
           - Mutlak platform tavanı: 500.000 TL
           - Mevcut teklifin 15× üzeri

        2. Soft ceiling (telefon doğrulaması olmayanlar için):
           - Eşik kontrolü ve katlama kontrolü
        """
        # ── Katman 1: Mutlak tavan — doğrulanmış olsa dahi geçerli ──
        if data_amount > _ABSOLUTE_MAX_BID_TL:
            await _log_fraud_attempt(
                "troll_bid_exceeds_platform_limit",
                stream_id=stream_id,
                user_id=user.id,
                username=user.username,
                extra={"amount": data_amount, "limit": _ABSOLUTE_MAX_BID_TL, "is_verified": user.is_verified},
            )
            raise BadRequestException(code="BID_EXCEEDS_MAX_PLATFORM_LIMIT")

        if current_bid >= _MULTIPLIER_MIN_BASE_TL and data_amount > current_bid * _MAX_MULTIPLIER_HARD:
            await _log_fraud_attempt(
                "troll_bid_exceeds_hard_multiplier",
                stream_id=stream_id,
                user_id=user.id,
                username=user.username,
                extra={"amount": data_amount, "current_bid": current_bid, "multiplier": _MAX_MULTIPLIER_HARD, "is_verified": user.is_verified},
            )
            raise BadRequestException(code="BID_MULTIPLIER_EXCEEDED")

        # ── Katman 2: Telefon doğrulaması gerektiren yumuşak eşik ──
        bid_threshold  = _HIGH_BID_THRESHOLD_TL if user.is_verified else _HIGH_BID_THRESHOLD_UNVERIFIED
        bid_multiplier = _HIGH_BID_MULTIPLIER   if user.is_verified else _HIGH_BID_MULTIPLIER_UNVERIFIED

        is_high_bid = (
            data_amount > bid_threshold
            or (
                current_bid >= _MULTIPLIER_MIN_BASE_TL
                and data_amount > current_bid * bid_multiplier
            )
        )

        if is_high_bid and (not user.phone or not user.phone_verified):
            await _log_fraud_attempt(
                "troll_bid_no_phone",
                stream_id=stream_id,
                user_id=user.id,
                username=user.username,
                extra={"amount": data_amount, "current_bid": current_bid, "is_verified": user.is_verified},
            )

            asyncio.create_task(track_user_event(
                event_type="bid_blocked_verify",
                item_id=stream_id,
                item_type="stream",
                user_id=user.id,
                price_point=data_amount,
            ))

            _verify_code = "BID_BLOCKED_NO_PHONE" if not user.phone else "BID_BLOCKED_PHONE_UNVERIFIED"
            raise ForbiddenException(code=_verify_code)
