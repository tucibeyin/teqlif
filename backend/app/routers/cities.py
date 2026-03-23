from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi_cache.decorator import cache
from app.database import get_db
from app.models.city import City

router = APIRouter(prefix="/api/cities", tags=["cities"])


@router.get("")
@cache(expire=86400)  # 24 saat — şehir listesi değişmez
async def get_cities(request: Request, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(City.name).order_by(City.sort_order))
    return [row[0] for row in result.all()]
