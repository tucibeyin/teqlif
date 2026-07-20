from sqlalchemy.exc import IntegrityError

from app.core.uow import AbstractUnitOfWork
from app.models.user import User
from app.models.enums import UserStatus
from app.schemas.block import BlockStatusOut
from app.core.exceptions import NotFoundException, BadRequestException
from app.core.logger import get_logger

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

        try:
            async with self.uow:
                target = await self.uow.users.get_by_username(username)
                
                if not target or target.status != UserStatus.ACTIVE:
                    logger.warning("[BlockUserUseCase] Kullanıcı bulunamadı | target_username=%s", username)
                    raise NotFoundException("Kullanıcı bulunamadı")
                    
                if target.id == current_user.id:
                    logger.warning("[BlockUserUseCase] Kendini engelleme teşebbüsü | user_id=%s", current_user.id)
                    raise BadRequestException("Kendinizi engelleyemezsiniz")

                await self.uow.users.add_block(current_user.id, target.id)
                await self.uow.commit()

        except IntegrityError:
            # SQLAlchemy UoW exception yakaladığında rollback otomatik yapılır.
            # Zaten engellenmiş olması durumunda unique constraint hatası fırlatılır.
            # Bunu idempotent bir işlem olarak varsayıp yutuyoruz.
            logger.info("[BlockUserUseCase] Zaten engellenmiş | blocker=%s target=%s", current_user.id, target.id)
        
        logger.info("[BlockUserUseCase] İşlem başarıyla tamamlandı | blocker=%s target=%s", current_user.id, target.id)
        return BlockStatusOut(is_blocked=True)
