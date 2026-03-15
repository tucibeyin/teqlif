from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_

from app.database import get_db
from app.models.user import User

router = APIRouter(prefix="/api/search", tags=["search"])


@router.get("/users")
async def search_users(q: str = "", db: AsyncSession = Depends(get_db)):
    if not q.strip():
        return []
    term = f"%{q.strip()}%"
    result = await db.execute(
        select(User)
        .where(
            User.is_active == True,  # noqa: E712
            or_(
                User.username.ilike(term),
                User.full_name.ilike(term),
            ),
        )
        .limit(20)
    )
    users = result.scalars().all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "profile_image_url": u.profile_image_url,
        }
        for u in users
    ]
