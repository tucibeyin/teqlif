from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.message import DirectMessage

VALID_REASONS = {"spam", "harassment", "inappropriate", "scam", "other"}


class FlagMessageCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, message_id: int, reason: str, requester_id: int) -> None:
        if reason not in VALID_REASONS:
            from app.core.exceptions import BadRequestException
            raise BadRequestException(code="INVALID_FLAG_REASON")

        async with self.uow:
            result = await self.uow.session.execute(
                select(DirectMessage).where(DirectMessage.id == message_id)
            )
            msg = result.scalar_one_or_none()
            if not msg:
                raise NotFoundException(code="MESSAGE_NOT_FOUND")
            if msg.receiver_id != requester_id:
                raise ForbiddenException(code="MESSAGE_FLAG_FORBIDDEN")
            msg.flag_reason = reason
