from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi_cache.decorator import cache
from app.database import get_db
from app.models.city import City
from app.models.district import District
from app.utils.schema_cache import static_schema_key_builder

router = APIRouter(prefix="/api/cities", tags=["cities"])


@router.get("")
@cache(expire=86400, key_builder=static_schema_key_builder)  # 24 saat — şehir listesi migration ile değişir
async def get_cities(request: Request, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(City.name).order_by(City.sort_order))
    return [row[0] for row in result.all()]


@router.get("/{province}/districts")
@cache(expire=86400, key_builder=static_schema_key_builder)
async def get_districts(province: str, request: Request, db: AsyncSession = Depends(get_db)):
    city_ids = select(City.id).where(City.name == province)
    result = await db.execute(
        select(District.name)
        .where(District.city_id.in_(city_ids))
        .distinct()
        .order_by(District.name)
    )
    return [row[0] for row in result.all()]
