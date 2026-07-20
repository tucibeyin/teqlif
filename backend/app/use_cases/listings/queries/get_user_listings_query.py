from typing import Optional
from sqlalchemy import select
from app.models.listing import Listing
from app.models.user import User
from app.models.enums import ListingStatus
from app.core.logger import get_logger

logger = get_logger(__name__)

class GetUserListingsQuery:
    """CQRS Query: Kullanıcının kendi ilanlarını getirir."""
    
    async def execute(
        self,
        db_session,
        current_user_id: int,
        active: Optional[bool] = None,
        q: Optional[str] = None,
        category: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None
    ) -> list:
        logger.info("[GetUserListingsQuery] Başlatıldı | user_id=%s active=%s", current_user_id, active)
        
        query = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.user_id == current_user_id, Listing.status != ListingStatus.DELETED)
        )
        if active is not None:
            if active:
                query = query.where(Listing.status == ListingStatus.ACTIVE)
            else:
                query = query.where(Listing.status != ListingStatus.ACTIVE)
                
        if category:
            query = query.where(Listing.category == category)
            
        if q:
            search_term = f"%{q}%"
            query = query.where(Listing.title.ilike(search_term))
            
        if start_date:
            query = query.where(Listing.created_at >= start_date)
        if end_date:
            query = query.where(Listing.created_at <= end_date)
            
        query = query.order_by(Listing.created_at.desc()).limit(limit).offset(offset)
        
        result = await db_session.execute(query)
        rows = result.all()
        
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "status": listing.status,
                "created_at": listing.created_at.isoformat() if listing.created_at else None,
                "image_url": listing.image_url,
                "user": {
                    "id": user.id,
                    "username": user.username
                }
            }
            for listing, user in rows
        ]
