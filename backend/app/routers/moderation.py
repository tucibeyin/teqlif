"""
Moderasyon endpoints — sadece yayın sahibi (host) kullanabilir.

POST /api/moderation/{stream_id}/mute     → kullanıcıyı sustur
POST /api/moderation/{stream_id}/unmute   → susturmayı kaldır
POST /api/moderation/{stream_id}/kick     → kullanıcıyı yayından at
GET  /api/moderation/{stream_id}/status   → mevcut mute/kick listelerini döndür (host)

Durum Redis'te tutulur (stream-scoped, 24 saat TTL):
  stream:{stream_id}:muted  → Set<user_id>
  stream:{stream_id}:kicked → Set<user_id>

Anlık event, moderation_broadcast kanalı üzerinden ilgili kullanıcıya iletilir.
"""
import json

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.auth import get_current_user
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/moderation", tags=["moderation"])


async def _remove_from_livekit(room_name: str, user_id: int) -> None:
    """Katılımcıyı LiveKit odasından zorla çıkar."""
    try:
        import aiohttp
        from livekit.api.room_service import RoomService, RoomParticipantIdentity
        from app.config import settings as _s
        api_url = _s.livekit_api_base
        logger.info("[MOD] LiveKit katılımcı çıkarılıyor | room=%s user_id=%s identity=%s api_url=%s",
                    room_name, user_id, str(user_id), api_url)
        async with aiohttp.ClientSession() as session:
            svc = RoomService(session, api_url, _s.livekit_api_key, _s.livekit_api_secret)
            req = RoomParticipantIdentity()
            req.room = room_name
            req.identity = str(user_id)
            await svc.remove_participant(req)
        logger.info("[MOD] LiveKit katılımcı çıkarıldı | room=%s user_id=%s", room_name, user_id)
    except Exception as exc:
        logger.warning("[MOD] LiveKit katılımcı çıkarılamadı | room=%s user_id=%s | %s", room_name, user_id, exc)

MOD_CHANNEL = "moderation_broadcast"
_TTL = 86_400  # 24 saat


def mute_key(stream_id: int) -> str:
    return f"stream:{stream_id}:muted"


def kick_key(stream_id: int) -> str:
    return f"stream:{stream_id}:kicked"


async def publish_mod_event(stream_id: int, event_type: str, target_user_id: int) -> None:
    """Tüm worker'lara moderasyon eventi yayınla."""
    redis = await get_redis()
    data = json.dumps({
        "_stream_id": stream_id,
        "type": event_type,
        "user_id": target_user_id,
    })
    await redis.publish(MOD_CHANNEL, data)


# ── Pydantic ────────────────────────────────────────────────────────────────

class _TargetIn(BaseModel):
    username: str


# ── Yardımcı ────────────────────────────────────────────────────────────────

async def _resolve(
    stream_id: int,
    username: str,
    current_user: User,
    db: AsyncSession,
) -> tuple[LiveStream, User]:
    """Host doğrula + hedef kullanıcıyı bul."""
    stream_res = await db.execute(
        select(LiveStream).where(LiveStream.id == stream_id)
    )
    stream = stream_res.scalar_one_or_none()
    if not stream or not stream.is_live:
        raise NotFoundException("Aktif yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise ForbiddenException("Sadece yayın sahibi moderasyon yapabilir")

    target_res = await db.execute(select(User).where(User.username == username))
    target = target_res.scalar_one_or_none()
    if not target:
        raise NotFoundException("Kullanıcı bulunamadı")
    if target.id == current_user.id:
        raise BadRequestException("Kendinize moderasyon uygulayamazsınız")

    return stream, target


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/{stream_id}/mute", status_code=status.HTTP_200_OK)
async def mute_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _, target = await _resolve(stream_id, body.username, current_user, db)

    redis = await get_redis()
    await redis.sadd(mute_key(stream_id), str(target.id))
    await redis.expire(mute_key(stream_id), _TTL)

    await publish_mod_event(stream_id, "muted", target.id)
    logger.info(
        "[MOD] MUTE | stream_id=%s host=%s target=%s",
        stream_id, current_user.username, target.username,
    )
    return {"message": f"@{target.username} susturuldu"}


@router.post("/{stream_id}/unmute", status_code=status.HTTP_200_OK)
async def unmute_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _, target = await _resolve(stream_id, body.username, current_user, db)

    redis = await get_redis()
    await redis.srem(mute_key(stream_id), str(target.id))

    await publish_mod_event(stream_id, "unmuted", target.id)
    logger.info(
        "[MOD] UNMUTE | stream_id=%s host=%s target=%s",
        stream_id, current_user.username, target.username,
    )
    return {"message": f"@{target.username} susturma kaldırıldı"}


@router.post("/{stream_id}/kick", status_code=status.HTTP_200_OK)
async def kick_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stream, target = await _resolve(stream_id, body.username, current_user, db)

    redis = await get_redis()
    await redis.sadd(kick_key(stream_id), str(target.id))
    await redis.expire(kick_key(stream_id), _TTL)

    await publish_mod_event(stream_id, "kicked", target.id)
    # LiveKit odasından zorla çıkar
    await _remove_from_livekit(stream.room_name, target.id)
    logger.info(
        "[MOD] KICK | stream_id=%s host=%s target=%s",
        stream_id, current_user.username, target.username,
    )
    return {"message": f"@{target.username} yayından atıldı"}


@router.get("/{stream_id}/status", status_code=status.HTTP_200_OK)
async def mod_status(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Host için mevcut mute/kick listelerini döndürür."""
    stream_res = await db.execute(
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

    return {
        "muted_user_ids": [int(x) for x in muted_ids],
        "kicked_user_ids": [int(x) for x in kicked_ids],
    }
