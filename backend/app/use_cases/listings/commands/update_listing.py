import json
from typing import Optional, Any
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException, ContentPolicyException, ForbiddenException
from app.core.auto_mod import analyze_listing_text
from app.use_cases.listings.commands.create_listing import VALID_CONDITIONS
from app.services import storage_service as storage

logger = get_logger(__name__)

# Sentinel: parametre hiç gönderilmedi (None'dan ayırt etmek için)
_UNSET: Any = object()


def _parse_url_set(raw) -> set:
    if not raw:
        return set()
    if isinstance(raw, list):
        return set(raw)
    try:
        parsed = json.loads(raw)
        return set(parsed) if isinstance(parsed, list) else set()
    except (json.JSONDecodeError, TypeError):
        return set()


def _derive_thumb_key(key: str) -> str:
    """abc123.jpg → abc123_thumb.jpg"""
    if "." not in key:
        return f"{key}_thumb.jpg"
    base, ext = key.rsplit(".", 1)
    thumb_ext = "jpg" if ext.lower() in ("jpg", "jpeg", "webp", "gif") else "png"
    return f"{base}_thumb.{thumb_ext}"


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
        image_urls: Any = _UNSET,    # list[str] | None | _UNSET ("iletilmedi" anlamı)
        image_url: Any = _UNSET,     # str | None | _UNSET
        thumbnail_url: Any = _UNSET, # str | None | _UNSET
        video_url: Any = _UNSET,     # str | None | _UNSET
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

        files_to_delete: list[str] = []

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
                listing.brand = extra_fields.get("brand")
                listing.model_name = extra_fields.get("model") or extra_fields.get("model_name")

            # ── Medya alanları ─────────────────────────────────────────────────
            if image_urls is not _UNSET:
                old_url_set = _parse_url_set(listing.image_urls)
                new_list = list(image_urls) if image_urls else []
                new_url_set = set(new_list)
                # Kaldırılan fotoğrafları MinIO'dan silinmek üzere işaretle
                for url in old_url_set - new_url_set:
                    if url.startswith("/uploads/"):
                        key = url[len("/uploads/"):]
                        files_to_delete.append(key)
                        files_to_delete.append(_derive_thumb_key(key))
                listing.image_urls = json.dumps(new_list) if new_list else None
                # Kapak fotoğrafını güncelle (image_url ayrıca iletilmediyse)
                if image_url is _UNSET:
                    listing.image_url = new_list[0] if new_list else None

            if image_url is not _UNSET:
                listing.image_url = image_url

            if thumbnail_url is not _UNSET:
                listing.thumbnail_url = thumbnail_url

            if video_url is not _UNSET:
                old_video = listing.video_url
                listing.video_url = video_url  # None = kaldır, str = güncelle
                if old_video and old_video != video_url and old_video.startswith("/uploads/"):
                    files_to_delete.append(old_video[len("/uploads/"):])

        # ── DB commit'ten sonra MinIO temizliği ────────────────────────────────
        for key in files_to_delete:
            try:
                storage.delete_object(key)
                logger.debug("[UpdateListing] MinIO silindi: %s", key)
            except Exception as exc:
                logger.warning("[UpdateListing] MinIO silme başarısız: key=%s | %s", key, exc)

        logger.info("[UpdateListingCommand] Başarılı | listing_id=%s | silinen_dosya=%d", listing_id, len(files_to_delete))
        return {"id": listing_id, "status": "updated"}
