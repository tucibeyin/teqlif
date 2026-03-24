"""
Kullanıcı profili ve engelleme servisi — iş mantığını router'dan ayırır.

UserService sınıfı; profil görüntüleme, kullanıcı engelleme/engel kaldırma
ve engellenen kullanıcı listesi gibi işlemleri yönetir.

Dependency Injection:
    db: AsyncSession — constructor üzerinden alınır (FastAPI Depends ile inject edilir)

Hata Yönetimi:
    DB yazma hataları       → logger.error + capture_exception → DatabaseException (500)
    Zaten engellenmiş (409) → IntegrityError yakalanır, idempotent olarak 200 döner
    İş kuralları             → BadRequest / NotFound
"""
from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError

from app.models.user import User
from app.models.listing import Listing
from app.models.follow import Follow
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.schemas.block import BlockedUserOut, BlockStatusOut
from app.core.exceptions import NotFoundException, BadRequestException, DatabaseException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


class UserService:
    """
    Kullanıcı profili ve engelleme iş mantığını barındıran servis sınıfı.

    Kullanım:
        svc = UserService(db)
        profile = await svc.get_profile("username", current_user)
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Engellenenleri Listele ────────────────────────────────────────────────
    async def list_blocked(self, current_user: User) -> List[User]:
        result = await self.db.execute(
            select(User)
            .join(UserBlock, UserBlock.blocked_id == User.id)
            .where(UserBlock.blocker_id == current_user.id)
            .order_by(UserBlock.created_at.desc())
        )
        return result.scalars().all()

    # ── Kullanıcı Engelle ─────────────────────────────────────────────────────
    async def block(self, username: str, current_user: User) -> BlockStatusOut:
        result = await self.db.execute(
            select(User).where(User.username == username, User.is_active == True)  # noqa: E712
        )
        target = result.scalar_one_or_none()
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")
        if target.id == current_user.id:
            raise BadRequestException("Kendinizi engelleyemezsiniz")

        block = UserBlock(blocker_id=current_user.id, blocked_id=target.id)
        self.db.add(block)
        try:
            await self.db.commit()
        except IntegrityError:
            # Zaten engellenmiş — idempotent, hata fırlatma
            await self.db.rollback()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[USERS] Engelleme DB hatası | blocker=%s blocked=%s | %s",
                current_user.id, target.id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Engelleme işlemi tamamlanamadı")

        return BlockStatusOut(is_blocked=True)

    # ── Engeli Kaldır ────────────────────────────────────────────────────────
    async def unblock(self, username: str, current_user: User) -> BlockStatusOut:
        result = await self.db.execute(
            select(User).where(User.username == username, User.is_active == True)  # noqa: E712
        )
        target = result.scalar_one_or_none()
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")

        block = await self.db.scalar(
            select(UserBlock).where(
                UserBlock.blocker_id == current_user.id,
                UserBlock.blocked_id == target.id,
            )
        )
        if block:
            await self.db.delete(block)
            try:
                await self.db.commit()
            except Exception as exc:
                await self.db.rollback()
                logger.error(
                    "[USERS] Engel kaldırma DB hatası | blocker=%s blocked=%s | %s",
                    current_user.id, target.id, exc, exc_info=True,
                )
                capture_exception(exc)
                raise DatabaseException("Engel kaldırma işlemi tamamlanamadı")

        return BlockStatusOut(is_blocked=False)

    # ── Kullanıcı Profili ────────────────────────────────────────────────────
    async def get_profile(self, username: str, current_user: Optional[User]) -> dict:
        result = await self.db.execute(
            select(User).where(User.username == username, User.is_active == True)  # noqa: E712
        )
        user = result.scalar_one_or_none()
        if not user:
            raise NotFoundException("Kullanıcı bulunamadı")

        listing_count = await self.db.scalar(
            select(func.count()).where(
                Listing.user_id == user.id,
                Listing.is_active == True,  # noqa: E712
            )
        ) or 0

        follower_count = await self.db.scalar(
            select(func.count()).where(Follow.followed_id == user.id)
        ) or 0

        following_count = await self.db.scalar(
            select(func.count()).where(Follow.follower_id == user.id)
        ) or 0

        is_following = False
        is_blocked = False
        if current_user and current_user.id != user.id:
            chk = await self.db.scalar(
                select(Follow).where(
                    Follow.follower_id == current_user.id,
                    Follow.followed_id == user.id,
                )
            )
            is_following = chk is not None

            block_chk = await self.db.scalar(
                select(UserBlock).where(
                    UserBlock.blocker_id == current_user.id,
                    UserBlock.blocked_id == user.id,
                )
            )
            is_blocked = block_chk is not None

        active_stream = await self.db.scalar(
            select(LiveStream).where(
                LiveStream.host_id == user.id,
                LiveStream.is_live == True,  # noqa: E712
            )
        )

        return {
            "id": user.id,
            "username": user.username,
            "full_name": user.full_name,
            "profile_image_url": user.profile_image_url,
            "listing_count": listing_count,
            "follower_count": follower_count,
            "following_count": following_count,
            "is_following": is_following,
            "is_blocked": is_blocked,
            "is_live": active_stream is not None,
            "active_stream_id": active_stream.id if active_stream else None,
        }
