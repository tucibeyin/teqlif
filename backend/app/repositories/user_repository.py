from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.user import User
from app.repositories.base_repository import BaseRepository

class UserRepository(BaseRepository[User]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(User, session)

    async def get_by_username(self, username: str) -> Optional[User]:
        result = await self.session.execute(select(User).filter(User.username == username))
        return result.scalars().first()

    async def get_by_email(self, email: str) -> Optional[User]:
        result = await self.session.execute(select(User).filter(User.email == email))
        return result.scalars().first()

    async def get_by_fcm_token(self, fcm_token: str) -> Optional[User]:
        result = await self.session.execute(select(User).filter(User.fcm_token == fcm_token))
        return result.scalars().first()

    async def add_block(self, blocker_id: int, blocked_id: int) -> None:
        from app.models.block import UserBlock
        block = UserBlock(blocker_id=blocker_id, blocked_id=blocked_id)
        self.session.add(block)

user_repository = UserRepository()
