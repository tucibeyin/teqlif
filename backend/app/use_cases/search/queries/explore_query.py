from typing import Optional

from sqlalchemy import select, func

from app.core.uow import AbstractUnitOfWork
from app.models.enums import ListingStatus
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.user import User
from app.models.user_interest import UserInterest
from app.use_cases.search.queries.search_utils import listing_dict, stream_dict


class ExploreQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user_id: Optional[int]) -> dict:
        if current_user_id:
            # Kişiselleştirilmiş: kullanıcının ilgi kategorisine uyan yayınlar önce
            # Stream block filtresi uygulanmaz — engellenen kullanıcı stream'leri görebilir
            stream_q = (
                select(LiveStream, func.coalesce(UserInterest.score, 0.0).label("cat_score"))
                .outerjoin(
                    UserInterest,
                    (UserInterest.user_id == current_user_id)
                    & (UserInterest.category == LiveStream.category),
                )
                .where(LiveStream.is_live == True)  # noqa: E712
                .order_by(
                    func.coalesce(UserInterest.score, 0.0).desc(),
                    LiveStream.started_at.desc(),
                )
                .limit(10)
            )
            streams_result = await self.uow.session.execute(stream_q)
            streams = [stream_dict(s) for s, _ in streams_result.all()]
            listings = []  # Giriş yapan için ilanlar /api/feed'den gelir
        else:
            stream_q = (
                select(LiveStream)
                .where(LiveStream.is_live == True)  # noqa: E712
                .order_by(LiveStream.started_at.desc())
                .limit(10)
            )
            streams_result = await self.uow.session.execute(stream_q)
            streams = [stream_dict(s) for s in streams_result.scalars().all()]

            listing_q = (
                select(Listing, User)
                .join(User, User.id == Listing.user_id)
                .where(Listing.status == ListingStatus.ACTIVE)  # noqa: E712
                .order_by(func.coalesce(Listing.reactivated_at, Listing.created_at).desc())
                .limit(20)
            )
            listings_result = await self.uow.session.execute(listing_q)
            listings = [listing_dict(l, u) for l, u in listings_result.all()]

        return {"listings": listings, "streams": streams}
