from typing import Optional
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException
# from app.use_cases.listings.projectors.listing_projector import READ_MODEL_LISTINGS_DETAIL

logger = get_logger(__name__)

class GetListingDetailsQuery:
    """CQRS Query: İlan detayını okuma modelinden (veya fallback DB'den) getirir."""
    
    async def execute(self, listing_id: int, current_user_id: Optional[int] = None) -> dict:
        logger.info("[GetListingDetailsQuery] Başlatıldı | listing_id=%s user_id=%s", listing_id, current_user_id)
        
        # Gerçek CQRS'te bu sorgu doğrudan Redis'e (örn: READ_MODEL_LISTINGS_DETAIL) gider.
        # Biz burada prototip olarak veritabanı simülasyonu yapıyoruz.
        
        from app.core.uow import SqlAlchemyUnitOfWork
        uow = SqlAlchemyUnitOfWork()
        async with uow:
            listing = await uow.listings.get(listing_id)
            if not listing:
                logger.warning("[GetListingDetailsQuery] İlan bulunamadı | listing_id=%s", listing_id)
                raise NotFoundException(code="LISTING_NOT_FOUND")
                
            # TODO: Return full mapped dict for ReadModel
            return {"id": listing.id, "title": listing.title, "price": listing.price}
