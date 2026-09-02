from sqlalchemy import select, func
from app.core.uow import AbstractUnitOfWork
from app.models.message import DirectMessage


class GetUnreadCountQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int) -> int:
        result = await self.uow.session.execute(
            select(func.count()).where(
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,
                DirectMessage.is_shadowbanned == False,
            )
        )
        return result.scalar_one()
