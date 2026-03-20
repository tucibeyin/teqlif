from typing import Optional
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_

from app.database import get_db
from app.models.user import User
from app.models.block import UserBlock
from app.utils.auth import bearer_scheme, decode_token

router = APIRouter(prefix="/api/search", tags=["search"])


async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("/users")
async def search_users(
    q: str = "",
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    if not q.strip():
        return []
    term = f"%{q.strip()}%"

    query = (
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

    # Engelleme filtresi: giriş yapmış kullanıcıdan engellenen veya onu engelleyen kişileri gizle
    if current_user_id:
        blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
        blocking_me = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
        query = query.where(
            User.id.not_in(blocked_by_me),
            User.id.not_in(blocking_me),
        )

    result = await db.execute(query)
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
