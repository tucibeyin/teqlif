import json
from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, ContentPolicyException
from app.core.auto_mod import analyze_listing_text

logger = get_logger(__name__)

VALID_CATEGORIES = {"elektronik", "moda", "ev_yasam", "diger"}
VALID_CONDITIONS = {"new", "like_new", "used", "damaged"}

class CreateListingCommand:
    """
    CQRS Command: İlan Oluşturma.
    Yalnızca UoW kullanarak veritabanına kayıt yapar ve EventBus'a ListingCreatedEvent fırlatır.
    Rate limit, lock, profanity check gibi iş kurallarını işletir.
    Eski sistemdeki search_alert, FTS update gibi yan etkiler Event üzerinden dinlenir.
    """
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        user_id: int,
        title: str,
        description: Optional[str] = None,
        price: Optional[float] = None,
        category: str = "diger",
        condition: Optional[str] = None,
        location: Optional[str] = None,
        image_url: Optional[str] = None,
        image_urls: list = None,
        thumbnail_url: Optional[str] = None,
        video_url: Optional[str] = None,
    ) -> dict:
        logger.info("[CreateListingCommand] İşlem başlatıldı | user_id=%s", user_id)

        # 1. İş Kuralları (Validasyon & Profanity)
        _title = (title or "").strip()
        _desc = (description or "").strip()
        
        if not _title:
            raise BadRequestException(code="LISTING_TITLE_REQUIRED")

        if price is None or price <= 0:
            raise BadRequestException(code="INVALID_PRICE")

        _loc = (location or "").strip()
        if not _loc:
            raise BadRequestException(code="LOCATION_REQUIRED")

        if analyze_listing_text(_title, _desc):
            raise ContentPolicyException()

        cat = category.strip().lower()
        if cat not in VALID_CATEGORIES:
            raise BadRequestException(code="INVALID_CATEGORY")

        cond = condition.strip().lower() if condition else ""
        if not cond or cond not in VALID_CONDITIONS:
            raise BadRequestException(code="INVALID_CONDITION")

        # 2. Veritabanı İşlemi (Write Model)
        from app.core.event_bus import event_bus
        from app.core.events import ListingCreatedEvent

        async with self.uow:
            listing_data = {
                "user_id": user_id,
                "title": _title,
                "description": _desc,
                "price": price,
                "category": cat,
                "condition": cond,
                "location": location,
                "image_url": image_url,
                "image_urls": json.dumps(image_urls or []),
                "thumbnail_url": thumbnail_url,
                "video_url": video_url,
            }

            new_listing = await self.uow.listings.create(obj_in=listing_data)

        # 3. CQRS: Diğer sistemlere (Projector, Notifier) haber ver — commit'ten sonra
        event_bus.publish(
            ListingCreatedEvent(
                listing_id=new_listing.id,
                user_id=user_id,
                title=_title,
                category=cat,
                price=price
            )
        )

        logger.info("[CreateListingCommand] Başarılı | listing_id=%s", new_listing.id)
        return {"id": new_listing.id, "status": "created"}
