from fastapi import APIRouter
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.category import Category

router = APIRouter(prefix="/api/categories", tags=["categories"])


@router.get("")
async def list_categories():
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Category)
            .where(Category.is_active == True)  # noqa: E712
            .order_by(Category.sort_order)
        )
        cats = result.scalars().all()
        return [{"key": c.key, "label": c.label} for c in cats]
