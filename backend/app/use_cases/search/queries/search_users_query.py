from typing import Optional

from sqlalchemy import select, or_

from app.core.uow import AbstractUnitOfWork
from app.models.enums import UserStatus
from app.models.user import User
from app.use_cases.search.queries.search_utils import block_filters


class SearchUsersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, q: str, offset: int, current_user_id: Optional[int]) -> list[dict]:
        q = q.strip()
        if not q:
            return []

        term = f"%{q}%"
        query = (
            select(User)
            .where(
                User.status == UserStatus.ACTIVE,
                or_(User.username.ilike(term), User.full_name.ilike(term)),
            )
            .offset(offset)
            .limit(20)
        )

        if current_user_id:
            query = block_filters(query, User.id, current_user_id)

        result = await self.uow.session.execute(query)
        return [
            {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            }
            for u in result.scalars().all()
        ]
