from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.user import User
from app.models.block import UserBlock

class GetBlockedUsersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user: User) -> list[User]:
        async with self.uow:
            query = (
                select(User)
                .join(UserBlock, UserBlock.blocked_id == User.id)
                .where(UserBlock.blocker_id == current_user.id)
            )
            result = await self.uow.session.execute(query)
            return list(result.scalars().all())
