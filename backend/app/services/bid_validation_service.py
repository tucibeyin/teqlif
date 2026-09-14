"""
Teklif doğrulama servisi - Troll teklif koruması ve temel limitleri yönetir.
Clean Architecture gereği auction_commands içinden izole edilmiştir.
"""

from app.models.user import User
from app.core.exceptions import ForbiddenException
from app.services.fraud_detection_service import _log_fraud_attempt
from app.database_clickhouse import track_user_event
import asyncio

# Telefon doğrulaması gerektiren mutlak teklif eşiği (TL)
_HIGH_BID_THRESHOLD_TL = 10_000
# Doğrulanmamış hesaplar için daha düşük eşik
_HIGH_BID_THRESHOLD_UNVERIFIED = 5_000
# Katlama kontrolü: mevcut teklif bu değerin üzerindeyken geçerli
_MULTIPLIER_MIN_BASE_TL = 500
# Mevcut fiyatın kaç katını aşarsa yüksek teklif sayılır — verified hesaplar
_HIGH_BID_MULTIPLIER = 10
# Mevcut fiyatın kaç katını aşarsa yüksek teklif sayılır — unverified hesaplar
_HIGH_BID_MULTIPLIER_UNVERIFIED = 7

class BidValidationService:
    @staticmethod
    async def validate_troll_bid(stream_id: int, user: User, data_amount: float, current_bid: float) -> None:
        """
        Kullanıcının verdiği teklifin troll (gerçekdışı / hatalı yüksek) bir teklif
        olup olmadığını kontrol eder. Eğer troll bir teklifse ve kullanıcının
        telefon doğrulaması yoksa exception fırlatır.
        """
        bid_threshold  = _HIGH_BID_THRESHOLD_TL if user.is_verified else _HIGH_BID_THRESHOLD_UNVERIFIED
        bid_multiplier = _HIGH_BID_MULTIPLIER if user.is_verified else _HIGH_BID_MULTIPLIER_UNVERIFIED
        
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
