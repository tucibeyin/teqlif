from sqlalchemy.exc import IntegrityError

from app.core.uow import AbstractUnitOfWork
from app.models.user import User
from app.models.enums import UserStatus
from app.schemas.block import BlockStatusOut
from app.core.exceptions import NotFoundException, ForbiddenException
from app.core.logger import get_logger
from app.services.relationship_service import RelationshipStateService

logger = get_logger(__name__)


class BlockUserUseCase:
    """
    Kullanıcı engelleme işlemini yürüten Use Case (Interactor).
    Sadece Unit of Work ve iş mantığına bağımlıdır.
    """

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: User) -> BlockStatusOut:
        logger.info("[BlockUserUseCase] İşlem başladı | blocker=%s target_username=%s", current_user.id, username)

        target_id = None
        session = None
        newly_blocked = False

        try:
            async with self.uow:
                target = await self.uow.users.get_by_username(username)

                if not target or target.status != UserStatus.ACTIVE:
                    logger.warning("[BlockUserUseCase] Kullanıcı bulunamadı | target_username=%s", username)
                    raise NotFoundException(code="USER_NOT_FOUND")

                if target.id == current_user.id:
                    logger.warning("[BlockUserUseCase] Kendini engelleme teşebbüsü | user_id=%s", current_user.id)
                    raise ForbiddenException(code="SELF_BLOCK_FORBIDDEN")

                await self.uow.users.add_block(current_user.id, target.id)
                target_id = target.id
                session = self.uow.session
                newly_blocked = True

        except IntegrityError:
            # Zaten engellenmiş: unique constraint hatası — idempotent olarak yutulur.
            logger.info("[BlockUserUseCase] Zaten engellenmiş | blocker=%s target=%s", current_user.id, target_id)

        logger.info("[BlockUserUseCase] İşlem tamamlandı | blocker=%s target=%s", current_user.id, target_id)

        if newly_blocked and target_id and session:
            state = await RelationshipStateService.recompute_and_cache(current_user.id, target_id, session)
            RelationshipStateService.broadcast(state)

        return BlockStatusOut(is_blocked=True)
