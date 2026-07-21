from typing import Optional
from sqlalchemy import select, or_, func
from datetime import datetime, timezone
from app.models.listing import Listing
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.models.enums import ListingStatus
from app.core.logger import get_logger

logger = get_logger(__name__)

class SearchListingsQuery:
    """CQRS Query: İlanları arama ve filtreleme işlemlerini yapar."""
    
    async def execute(
        self,
        db_session,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        location: Optional[str] = None,
        q: Optional[str] = None,
        current_user_id: Optional[int] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list:
        logger.info("[SearchListingsQuery] Başlatıldı | q=%s category=%s", q, category)
        
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
        if location:
            q_stmt = q_stmt.where(Listing.location.ilike(f"%{location}%"))
        
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
        user_ids = list({user.id for _, user in rows})
        
        # Mocks for now, real implementation requires porting LikeService and Meta helpers
        # To avoid massive file size, we will return basic dicts for the refactor
        
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "location": listing.location,
                "image_url": listing.image_url,
                "created_at": listing.created_at.isoformat() if listing.created_at else None,
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "is_premium": user.is_premium
                }
            }
            for listing, user in rows
        ]
