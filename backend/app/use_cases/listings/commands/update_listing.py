from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException, ContentPolicyException, ForbiddenException
from app.core.auto_mod import analyze_listing_text
from app.use_cases.listings.commands.create_listing import VALID_CONDITIONS

logger = get_logger(__name__)


class UpdateListingCommand:
    """CQRS Command: Mevcut bir ilanı günceller."""

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        listing_id: int,
        user_id: int,
        title: Optional[str] = None,
        description: Optional[str] = None,
        price: Optional[float] = None,
        category: Optional[str] = None,
        subcategory: Optional[str] = None,
        condition: Optional[str] = None,
        province: Optional[str] = None,
        district: Optional[str] = None,
        extra_fields: Optional[dict] = None,
    ) -> dict:
        logger.info("[UpdateListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, user_id)

        if title is not None and not title.strip():
            raise BadRequestException(code="LISTING_TITLE_REQUIRED")

        if condition is not None:
            cond = condition.strip().lower()
            if cond not in VALID_CONDITIONS:
                raise BadRequestException(code="INVALID_CONDITION")

        if title or description:
            if analyze_listing_text(title or "", description or ""):
                raise ContentPolicyException()

        async with self.uow:
            listing = await self.uow.listings.get(listing_id)
            if not listing:
                raise NotFoundException(code="LISTING_NOT_FOUND")

            if listing.user_id != user_id:
                raise ForbiddenException(code="LISTING_UPDATE_FORBIDDEN")

            if title is not None:
                listing.title = title.strip()
            if description is not None:
                listing.description = description.strip()
            if price is not None:
                listing.price = price
            if category is not None:
                listing.category = category.strip().lower()
            if subcategory is not None:
                listing.subcategory = subcategory.strip().lower()
            if condition is not None:
                listing.condition = condition.strip().lower()
            if province is not None:
                listing.province = province.strip()
                listing.location = province.strip()  # backward compat
            if district is not None:
                listing.district = district.strip() or None
            if extra_fields is not None:
                listing.extra_fields = extra_fields or None
                # brand / model_name güncelle
                listing.brand = extra_fields.get("marka") or extra_fields.get("brand")
                listing.model_name = extra_fields.get("model") or extra_fields.get("model_name")

        logger.info("[UpdateListingCommand] Başarılı | listing_id=%s", listing_id)
        return {"id": listing_id, "status": "updated"}
