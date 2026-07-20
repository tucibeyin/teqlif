from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.listing import ListingOffer
from app.models.user import User

class GetListingOffersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int) -> list:
        async with self.uow:
            query = (
                select(ListingOffer, User)
                .join(User, User.id == ListingOffer.user_id)
                .where(ListingOffer.listing_id == listing_id)
                .order_by(ListingOffer.created_at.desc())
            )
            result = await self.uow.session.execute(query)
            rows = result.all()
            
            return [
                {
                    "id": offer.id,
                    "amount": offer.amount,
                    "created_at": offer.created_at,
                    "user": {
                        "id": user.id,
                        "username": user.username,
                        "avatar_url": user.avatar_url
                    }
                }
                for offer, user in rows
            ]
