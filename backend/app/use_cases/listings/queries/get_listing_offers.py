from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing
from app.models.listing_offer import ListingOffer
from app.models.user import User


class GetListingOffersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        listing_id: int,
        current_user_id: int,
        limit: int = 20,
        offset: int = 0,
    ) -> list:
        # İlan sahibini doğrula
        listing_result = await self.uow.session.execute(
            select(Listing.user_id).where(Listing.id == listing_id)
        )
        owner_id = listing_result.scalar_one_or_none()
        if owner_id is None:
            return []

        is_owner = current_user_id == owner_id

        query = (
            select(ListingOffer, User)
            .join(User, User.id == ListingOffer.user_id)
            .where(ListingOffer.listing_id == listing_id)
            .order_by(ListingOffer.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        # Sahip değilse yalnızca kendi teklifini görebilir
        if not is_owner:
            query = query.where(ListingOffer.user_id == current_user_id)

        result = await self.uow.session.execute(query)
        rows = result.all()

        return [
            {
                "id": offer.id,
                "amount": offer.amount,
                "status": offer.status,
                "created_at": offer.created_at,
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "avatar_url": user.profile_image_url,
                },
            }
            for offer, user in rows
        ]
