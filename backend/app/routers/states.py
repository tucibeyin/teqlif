from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi_cache.decorator import cache
from app.database import get_db
from app.models.state import State
from app.models.district import District
from app.utils.schema_cache import static_schema_key_builder

router = APIRouter(prefix="/api/states", tags=["states"])


@router.get("")
@cache(expire=86400, key_builder=static_schema_key_builder)
async def get_states(request: Request, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(State.name).order_by(State.sort_order))
    return [row[0] for row in result.all()]


@router.get("/{province}/districts")
@cache(expire=86400, key_builder=static_schema_key_builder)
async def get_districts(province: str, request: Request, db: AsyncSession = Depends(get_db)):
    subq = select(State.id).where(State.name == province).scalar_subquery()
    result = await db.execute(
        select(District.name)
        .where(District.state_id == subq)
        .order_by(District.name)
    )
    return [row[0] for row in result.all()]
