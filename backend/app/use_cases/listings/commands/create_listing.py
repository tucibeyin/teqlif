import json
from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, ContentPolicyException
from app.core.auto_mod import analyze_listing_text

logger = get_logger(__name__)

VALID_CATEGORIES = {
    "electronics", "vehicles", "real_estate", "fashion", "home", "sports", "books", "other"
}

VALID_CONDITIONS = {"new", "like_new", "used", "damaged", "refurbished"}


class CreateListingCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        user_id: int,
        title: str,
        description: Optional[str] = None,
        price: Optional[float] = None,
        category: str = "other",
        subcategory: Optional[str] = None,
        condition: Optional[str] = None,
        province: Optional[str] = None,
        district: Optional[str] = None,
        extra_fields: Optional[dict] = None,
        image_url: Optional[str] = None,
        image_urls: list = None,
        thumbnail_url: Optional[str] = None,
        video_url: Optional[str] = None,
    ) -> dict:
        logger.info("[CreateListingCommand] İşlem başlatıldı | user_id=%s", user_id)

        _title = (title or "").strip()
        _desc = (description or "").strip()

        if not _title:
            raise BadRequestException(code="LISTING_TITLE_REQUIRED")

        if price is None or price <= 0:
            raise BadRequestException(code="INVALID_PRICE")

        _province = (province or "").strip()
        if not _province:
            raise BadRequestException(code="PROVINCE_REQUIRED")

        if analyze_listing_text(_title, _desc):
            raise ContentPolicyException()

        cat = category.strip().lower()
        if cat not in VALID_CATEGORIES:
            cat = "other"

        cond = condition.strip().lower() if condition else ""
        if not cond or cond not in VALID_CONDITIONS:
            raise BadRequestException(code="INVALID_CONDITION")

        # brand / model_name: extra_fields'den çıkar, arama indexleri için dedicated kolonlara yaz
        ef = extra_fields or {}
        brand = ef.get("brand")
        model_name = ef.get("model") or ef.get("model_name")

        async with self.uow:
            listing_data = {
                "user_id": user_id,
                "title": _title,
                "description": _desc,
                "price": price,
                "category": cat,
                "subcategory": (subcategory or "").strip().lower() or None,
                "condition": cond,
                "province": _province,
                "district": (district or "").strip() or None,
                "location": _province,  # backward compat: feed/search sorgularında hâlâ okunuyor
                "extra_fields": ef or None,
                "brand": brand,
                "model_name": model_name,
                "image_url": image_url,
                "image_urls": json.dumps(image_urls or []),
                "thumbnail_url": thumbnail_url,
                "video_url": video_url,
            }

            new_listing = await self.uow.listings.create(obj_in=listing_data)

        from app.core.event_bus import event_bus
        from app.core.events import ListingCreatedEvent

        event_bus.publish(
            ListingCreatedEvent(
                listing_id=new_listing.id,
                user_id=user_id,
                title=_title,
                category=cat,
                price=price,
            )
        )

        logger.info("[CreateListingCommand] Başarılı | listing_id=%s", new_listing.id)
        return {"id": new_listing.id, "status": "created"}
