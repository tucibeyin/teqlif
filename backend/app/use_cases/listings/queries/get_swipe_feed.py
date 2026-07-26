from sqlalchemy import select, func, case, desc, nullslast
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.user import User

class GetSwipeFeedQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        limit: int = 10,
        preferred_categories: list[str] | None = None,
    ) -> list:
        base_where = [
            Listing.status == ListingStatus.ACTIVE,
            Listing.status != ListingStatus.DELETED,
            (Listing.video_url.isnot(None)) | (Listing.image_url.isnot(None)),
        ]

        if preferred_categories:
            # Preferred kategoriler önce (rank 0..N), diğerleri sonra — ikincil: quality DESC, random
            cat_rank = case(
                *[
                    (Listing.category == cat, idx)
                    for idx, cat in enumerate(preferred_categories)
                ],
                else_=len(preferred_categories),
            )
            order_clauses = [cat_rank, desc(nullslast(Listing.quality_score)), func.random()]
        else:
            order_clauses = [func.random()]

        query = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(*base_where)
            .order_by(*order_clauses)
            .limit(limit)
        )
        result = await self.uow.session.execute(query)
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "subcategory": listing.subcategory,
                "location": listing.location,
                "video_url": listing.video_url,
                "thumbnail_url": listing.thumbnail_url,
                "image_url": listing.image_url,
                "user": {"id": user.id, "username": user.username},
            }
            for listing, user in result.all()
        ]
