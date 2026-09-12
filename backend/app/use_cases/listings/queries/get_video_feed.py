from sqlalchemy import select, func, text
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.user import User

class GetVideoFeedQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, limit: int = 8) -> list:
        # TABLESAMPLE yerine büyük offset + LIMIT ile ucuz random sample:
        # önce tablodaki aktif video ilan sayısını al, rastgele offset seç.
        # ORDER BY RANDOM() tablo boyutuyla O(N log N)'e ölçeklenir.
        count_result = await self.uow.session.scalar(
            select(func.count()).select_from(Listing).where(
                Listing.status == ListingStatus.ACTIVE,
                Listing.video_url.isnot(None),
            )
        )
        total = count_result or 0
        import random
        offset = random.randint(0, max(0, total - limit)) if total > limit else 0

        query = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.status == ListingStatus.ACTIVE,
                Listing.video_url.isnot(None),
            )
            .order_by(Listing.id)
            .offset(offset)
            .limit(limit)
        )
        result = await self.uow.session.execute(query)
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "location": listing.location,
                "video_url": listing.video_url,
                "thumbnail_url": listing.thumbnail_url,
                "image_url": listing.image_url,
                "user": {"id": user.id, "username": user.username},
            }
            for listing, user in result.all()
        ]
