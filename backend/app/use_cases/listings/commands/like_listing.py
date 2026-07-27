from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.enums import ListingStatus

logger = get_logger(__name__)

class LikeListingCommand:
    """CQRS Command: Bir ilanı favorilere ekler veya çıkarır (Toggle)."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, user_id: int) -> dict:
        logger.info("[LikeListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, user_id)

        from app.models.favorite import Favorite
        from app.models.like import ListingLike

        async with self.uow:
            listing = await self.uow.listings.get(listing_id)
            if not listing or listing.status != ListingStatus.ACTIVE:
                logger.warning("[LikeListingCommand] İlan aktif değil veya bulunamadı | listing_id=%s", listing_id)
                raise NotFoundException(code="LISTING_NOT_FOUND")

            if listing.user_id == user_id:
                logger.warning("[LikeListingCommand] Kendi ilanını beğenme engellendi | listing_id=%s", listing_id)
                raise ForbiddenException(code="SELF_FAVORITE_FORBIDDEN")

            from sqlalchemy import select
            stmt_fav = select(Favorite).where(Favorite.user_id == user_id, Favorite.listing_id == listing_id)
            res_fav = await self.uow.session.execute(stmt_fav)
            favorite = res_fav.scalar_one_or_none()

            stmt_like = select(ListingLike).where(ListingLike.user_id == user_id, ListingLike.listing_id == listing_id)
            res_like = await self.uow.session.execute(stmt_like)
            like_obj = res_like.scalar_one_or_none()

            action = "liked"
            if favorite or like_obj:
                if favorite:
                    await self.uow.session.delete(favorite)
                if like_obj:
                    await self.uow.session.delete(like_obj)
                action = "unliked"
                logger.info("[LikeListingCommand] Beğeni ve favoriden çıkarıldı | listing_id=%s", listing_id)
            else:
                self.uow.session.add(Favorite(user_id=user_id, listing_id=listing_id))
                self.uow.session.add(ListingLike(user_id=user_id, listing_id=listing_id))
                logger.info("[LikeListingCommand] Beğeni ve favoriye eklendi | listing_id=%s", listing_id)

            # TODO: EventBus publish ListingLikedEvent

        return {"id": listing_id, "action": action, "is_liked": action == "liked", "is_favorited": action == "liked"}
