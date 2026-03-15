from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.city import City

router = APIRouter(prefix="/api/cities", tags=["cities"])


@router.get("")
async def get_cities(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(City.name).order_by(City.sort_order))
    return [row[0] for row in result.all()]
