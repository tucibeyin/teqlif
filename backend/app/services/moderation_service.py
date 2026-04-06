"""
Moderasyon servisi — iş mantığını router'dan ayırır.

ModerationService sınıfı; mute/unmute/kick/promote/demote gibi tüm
moderasyon işlemlerini, Redis state yönetimini, Pub/Sub event
yayınlarını ve LiveKit katılımcı çıkarma işlemlerini yönetir.

Dependency Injection:
    db: AsyncSession — constructor üzerinden alınır

Redis key fonksiyonları (mute_key, kick_key, mod_key) ve MOD_CHANNEL
sabiti bu modülde tanımlanır; diğer modüller buradan import eder.

Hata Yönetimi:
    İş kuralları → BadRequest / Forbidden / NotFound (HTTP exception)
    LiveKit hataları → logger.warning (non-critical, işlem yine de tamamlanır)
"""
import json

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException
from app.core.logger import get_logger
from app.constants import ws_types as WS

logger = get_logger(__name__)

# ── Sabitler ─────────────────────────────────────────────────────────────────
MOD_CHANNEL = "moderation_broadcast"
_TTL = 86_400  # 24 saat


# ── Redis key yardımcıları (diğer modüller buradan import eder) ───────────────
def mute_key(stream_id: int) -> str:
    return f"stream:{stream_id}:muted"


def kick_key(stream_id: int) -> str:
    return f"stream:{stream_id}:kicked"


def mod_key(stream_id: int) -> str:
    return f"stream:{stream_id}:mods"


# ── Pub/Sub yardımcısı ───────────────────────────────────────────────────────
async def publish_mod_event(
    stream_id: int,
    event_type: str,
    target_user_id: int,
    **extra,
) -> None:
    """Tüm worker'lara moderasyon eventi yayınla.

    extra kwargs payload'a düz olarak eklenir (örn: username=, promoted_by=).
    """
    redis = await get_redis()
    data = json.dumps({
        "_stream_id": stream_id,
        "type": event_type,
        "user_id": target_user_id,
        **extra,
    })
    await redis.publish(MOD_CHANNEL, data)


# ── LiveKit yardımcısı ───────────────────────────────────────────────────────
async def remove_from_livekit(room_name: str, user_id: int) -> None:
    """Katılımcıyı LiveKit odasından zorla çıkar (non-critical)."""
    try:
        import aiohttp
        from livekit.api.room_service import RoomService, RoomParticipantIdentity
        from app.config import settings as _s
        api_url = _s.livekit_api_base
        logger.info(
            "[MOD] LiveKit katılımcı çıkarılıyor | room=%s user_id=%s identity=%s api_url=%s",
            room_name, user_id, str(user_id), api_url,
        )
        async with aiohttp.ClientSession() as session:
            svc = RoomService(session, api_url, _s.livekit_api_key, _s.livekit_api_secret)
            req = RoomParticipantIdentity()
            req.room = room_name
            req.identity = str(user_id)
            await svc.remove_participant(req)
        logger.info("[MOD] LiveKit katılımcı çıkarıldı | room=%s user_id=%s", room_name, user_id)
    except Exception as exc:
        logger.warning(
            "[MOD] LiveKit katılımcı çıkarılamadı | room=%s user_id=%s | %s",
            room_name, user_id, exc,
        )


# ── Servis sınıfı ────────────────────────────────────────────────────────────
class ModerationService:
    """
    Tüm moderasyon iş mantığını barındıran servis sınıfı.

    Kullanım:
        svc = ModerationService(db)
        result = await svc.mute(stream_id, body.username, current_user)
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Yardımcı: yetki doğrula + hedef kullanıcıyı bul ─────────────────────
    async def _resolve_actors(
        self,
        stream_id: int,
        username: str,
        current_user: User,
        *,
        host_only: bool = False,
    ) -> tuple[LiveStream, User]:
        """
        Yetki doğrula (host veya co-host) + hedef kullanıcıyı bul.

        host_only=True  → sadece yayın sahibi geçebilir (promote/demote gibi kritik işlemler).
        host_only=False → host VEYA Redis mods set'indeki co-host geçebilir.
        """
        stream_res = await self.db.execute(
            select(LiveStream).where(LiveStream.id == stream_id)
        )
        stream = stream_res.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")

        is_host = stream.host_id == current_user.id

        if not is_host:
            if host_only:
                raise ForbiddenException("Sadece yayın sahibi bu işlemi yapabilir")
            # Co-host kontrolü: Redis mods set'inde mi?
            redis = await get_redis()
            is_mod = await redis.sismember(mod_key(stream_id), str(current_user.id))
            if not is_mod:
                raise ForbiddenException("Bu işlem için yetkiniz yok")

        target_res = await self.db.execute(select(User).where(User.username == username))
        target = target_res.scalar_one_or_none()
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")
        if target.id == current_user.id:
            raise BadRequestException("Kendinize moderasyon uygulayamazsınız")
        # Co-host, yayın sahibini hedef alamaz
        if not is_host and target.id == stream.host_id:
            raise ForbiddenException("Moderatör, yayın sahibine işlem yapamaz")

        return stream, target

    # ── Sustur ───────────────────────────────────────────────────────────────
    async def mute(self, stream_id: int, username: str, current_user: User) -> dict:
        _, target = await self._resolve_actors(stream_id, username, current_user)

        redis = await get_redis()
        await redis.sadd(mute_key(stream_id), str(target.id))
        await redis.expire(mute_key(stream_id), _TTL)

        await publish_mod_event(stream_id, WS.MUTED, target.id)
        logger.info(
            "[MOD] MUTE | stream_id=%s by=%s target=%s",
            stream_id, current_user.username, target.username,
        )
        return {"message": f"@{target.username} susturuldu"}

    # ── Susturmayı Kaldır ────────────────────────────────────────────────────
    async def unmute(self, stream_id: int, username: str, current_user: User) -> dict:
        _, target = await self._resolve_actors(stream_id, username, current_user)

        redis = await get_redis()
        await redis.srem(mute_key(stream_id), str(target.id))

        await publish_mod_event(stream_id, WS.UNMUTED, target.id)
        logger.info(
            "[MOD] UNMUTE | stream_id=%s by=%s target=%s",
            stream_id, current_user.username, target.username,
        )
        return {"message": f"@{target.username} susturma kaldırıldı"}

    # ── Yayından At ──────────────────────────────────────────────────────────
    async def kick(self, stream_id: int, username: str, current_user: User) -> dict:
        stream, target = await self._resolve_actors(stream_id, username, current_user)

        redis = await get_redis()
        await redis.sadd(kick_key(stream_id), str(target.id))
        await redis.expire(kick_key(stream_id), _TTL)

        await publish_mod_event(stream_id, WS.KICKED, target.id)
        # LiveKit odasından zorla çıkar
        await remove_from_livekit(stream.room_name, target.id)
        logger.info(
            "[MOD] KICK | stream_id=%s by=%s target=%s",
            stream_id, current_user.username, target.username,
        )
        return {"message": f"@{target.username} yayından atıldı"}

    # ── Moderatör Ata ─────────────────────────────────────────────────────────
    async def promote(self, stream_id: int, username: str, current_user: User) -> dict:
        """İzleyiciyi Co-Host (moderatör) olarak atar. Sadece host çağırabilir."""
        _, target = await self._resolve_actors(
            stream_id, username, current_user, host_only=True
        )

        redis = await get_redis()
        await redis.sadd(mod_key(stream_id), str(target.id))
        await redis.expire(mod_key(stream_id), _TTL)

        await publish_mod_event(
            stream_id,
            WS.MOD_PROMOTED,
            target.id,
            username=target.username,
            promoted_by=current_user.username,
        )
        logger.info(
            "[MOD] PROMOTE | stream_id=%s by=%s target=%s",
            stream_id, current_user.username, target.username,
        )
        return {"message": f"@{target.username} moderatör yapıldı"}

    # ── Moderatörlüğü Geri Al ────────────────────────────────────────────────
    async def demote(self, stream_id: int, username: str, current_user: User) -> dict:
        """Kullanıcının moderatörlüğünü geri alır. Sadece host çağırabilir."""
        _, target = await self._resolve_actors(
            stream_id, username, current_user, host_only=True
        )

        redis = await get_redis()
        await redis.srem(mod_key(stream_id), str(target.id))

        await publish_mod_event(
            stream_id,
            WS.MOD_DEMOTED,
            target.id,
            username=target.username,
            demoted_by=current_user.username,
        )
        logger.info(
            "[MOD] DEMOTE | stream_id=%s by=%s target=%s",
            stream_id, current_user.username, target.username,
        )
        return {"message": f"@{target.username} moderatörlükten alındı"}

    # ── Moderatör Listesi ────────────────────────────────────────────────────
    async def list_mods(self, stream_id: int, current_user: User) -> dict:
        """Aktif moderatör listesini döndürür (tüm kimliği doğrulanmış izleyiciler görebilir)."""
        stream_res = await self.db.execute(
            select(LiveStream).where(
                LiveStream.id == stream_id,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        if not stream_res.scalar_one_or_none():
            raise NotFoundException("Aktif yayın bulunamadı")

        redis = await get_redis()
        mod_ids = await redis.smembers(mod_key(stream_id))
        return {"mod_user_ids": [int(x) for x in mod_ids]}

    # ── Moderasyon Durumu ────────────────────────────────────────────────────
    async def get_status(self, stream_id: int, current_user: User) -> dict:
        """Host için mevcut mute/kick/mods listelerini döndürür."""
        stream_res = await self.db.execute(
            select(LiveStream).where(LiveStream.id == stream_id)
        )
        stream = stream_res.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id != current_user.id:
            raise ForbiddenException("Sadece yayın sahibi görebilir")

        redis = await get_redis()
        muted_ids = await redis.smembers(mute_key(stream_id))
        kicked_ids = await redis.smembers(kick_key(stream_id))
        mod_ids = await redis.smembers(mod_key(stream_id))

        return {
            "muted_user_ids": [int(x) for x in muted_ids],
            "kicked_user_ids": [int(x) for x in kicked_ids],
            "mod_user_ids": [int(x) for x in mod_ids],
        }
