from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.utils.auth import get_current_user_optional
from app.models.user import User
from app.services.feed_service import get_personalized_feed

router = APIRouter(prefix="/api/feed", tags=["feed"])


@router.get("")
async def get_feed(
    page: int = Query(default=0, ge=0, le=100),
    seed: str = Query(default="default", max_length=64),
    db: AsyncSession = Depends(get_db),
    current_user: User | None = Depends(get_current_user_optional),
):
    """
    Kişiselleştirilmiş ilan akışı.

    - Giriş yapmış kullanıcılar: kategori ilgisine göre sıralı feed
    - Misafirler: popüler ilanlar (son 30 gün, beğeni sayısına göre)
    - page: 0-tabanlı sayfa numarası (sayfa başına 20 ilan)
    - seed: oturum başında üretilmeli, scroll boyunca aynı kalmalı
    """
    user_id = current_user.id if current_user else None
    return await get_personalized_feed(user_id, page, seed, db)
