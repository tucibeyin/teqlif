from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi_cache.decorator import cache
from app.database import get_db
from app.models.city import City
from app.models.district import District

router = APIRouter(prefix="/api/cities", tags=["cities"])


@router.get("")
@cache(expire=86400)  # 24 saat — şehir listesi değişmez
async def get_cities(request: Request, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(City.name).order_by(City.sort_order))
    return [row[0] for row in result.all()]


@router.get("/{province}/districts")
@cache(expire=86400)
async def get_districts(province: str, request: Request, db: AsyncSession = Depends(get_db)):
    subq = select(City.id).where(City.name == province).scalar_subquery()
    result = await db.execute(
        select(District.name)
        .where(District.city_id == subq)
        .order_by(District.name)
    )
    return [row[0] for row in result.all()]
