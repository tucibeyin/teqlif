from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.utils.auth import get_current_user, get_current_user_optional
from app.models.user import User
from app.services.feed_service import get_personalized_feed, get_foryou_feed

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


@router.get("/for-you")
async def get_for_you_feed(
    page: int = Query(default=0, ge=0, le=4),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Embedding tabanlı kişisel 'Sana Özel' akışı.

    - preference_embedding yoksa cold start (popüler ilanlar)
    - varsa pgvector cosine distance ile en yakın ilanlar
    - Sayfa başına 20 ilan, maks 5 sayfa (100 ilan havuzu Redis'te 5 dk önbelleklenir)
    """
    return await get_foryou_feed(current_user.id, page, db)
