from typing import Optional
from sqlalchemy import select, or_, func
from datetime import datetime, timezone, timedelta
from app.models.listing import Listing
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.models.enums import ListingStatus
from app.use_cases.listings.queries.listing_utils import _parse_image_urls
from app.services.like_service import LikeService
from app.core.logger import get_logger

logger = get_logger(__name__)

class SearchListingsQuery:
    """CQRS Query: İlanları arama ve filtreleme işlemlerini yapar."""
    
    async def execute(
        self,
        db_session,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        subcategory: Optional[str] = None,
        location: Optional[str] = None,
        q: Optional[str] = None,
        current_user_id: Optional[int] = None,
        limit: int = 50,
        offset: int = 0,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> list:
        logger.info("[SearchListingsQuery] Başlatıldı | q=%s category=%s date_from=%s date_to=%s", q, category, date_from, date_to)
        
        q_stmt = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.status == ListingStatus.ACTIVE,
                Listing.status != ListingStatus.DELETED,
                or_(Listing.expires_at == None, Listing.expires_at > datetime.now(timezone.utc)),
            )
        )
        if user_id:
            q_stmt = q_stmt.where(Listing.user_id == user_id)
        elif current_user_id:
            # Genel listeleme: kullanıcının kendi ilanlarını gizle
            q_stmt = q_stmt.where(Listing.user_id != current_user_id)
        if category:
            q_stmt = q_stmt.where(Listing.category == category)
        if subcategory:
            q_stmt = q_stmt.where(Listing.subcategory == subcategory)
        if location:
            q_stmt = q_stmt.where(Listing.location.ilike(f"%{location}%"))
        if date_from:
            try:
                sd = datetime.strptime(date_from, '%Y-%m-%d')
                q_stmt = q_stmt.where(Listing.created_at >= sd)
            except ValueError:
                pass
        if date_to:
            try:
                ed = datetime.strptime(date_to, '%Y-%m-%d') + timedelta(days=1)
                q_stmt = q_stmt.where(Listing.created_at < ed)
            except ValueError:
                pass
        
        if q:
            search_term = f"%{q}%"
            q_stmt = q_stmt.where(
                or_(
                    Listing.title.ilike(search_term),
                    Listing.description.ilike(search_term),
                    Listing.title.op('%')(q),
                    func.similarity(Listing.title, q) > 0.15,
                    func.similarity(Listing.description, q) > 0.15
                )
            )
            q_stmt = q_stmt.order_by(
                func.greatest(
                    func.similarity(Listing.title, q),
                    func.similarity(Listing.description, q)
                ).desc(),
                User.is_premium.desc(), 
                Listing.created_at.desc()
            ).limit(limit).offset(offset)
        else:
            q_stmt = q_stmt.order_by(User.is_premium.desc(), Listing.created_at.desc()).limit(limit).offset(offset)
            
        result = await db_session.execute(q_stmt)
        rows = result.all()

        listing_ids = [listing.id for listing, _ in rows]
        counts, liked_set = await LikeService.batch_listing_likes(db_session, listing_ids, current_user_id)

        return [
            {
                "id": listing.id,
                "title": listing.title,
                "description": listing.description,
                "price": listing.price,
                "category": listing.category,
                "location": listing.location,
                "image_url": listing.image_url,
                "image_urls": _parse_image_urls(listing.image_urls),
                "status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status),
                "created_at": listing.created_at.isoformat() if listing.created_at else None,
                "likes_count": counts.get(listing.id, 0),
                "is_liked": listing.id in liked_set,
                "is_favorited": listing.id in liked_set,
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "is_premium": user.is_premium
                }
            }
            for listing, user in rows
        ]
