from sqlalchemy import select, func
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing, ListingStatus
from app.models.user import User

class GetVideoFeedQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, limit: int = 8) -> list:
        async with self.uow:
            query = (
                select(Listing, User)
                .join(User, User.id == Listing.user_id)
                .where(
                    Listing.status == ListingStatus.ACTIVE,
                    Listing.status != ListingStatus.DELETED,
                    Listing.video_url.isnot(None),
                )
                .order_by(func.random())
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
