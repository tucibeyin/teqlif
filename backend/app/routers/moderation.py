"""
Moderasyon router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db) alır
  2. ModerationService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, Redis state yönetimi, LiveKit çıkarma ve Pub/Sub event
yayınları tamamen app.services.moderation_service.ModerationService'e
taşınmıştır.

Geriye dönük uyumluluk (backward compatibility):
  mute_key, kick_key, mod_key, MOD_CHANNEL, publish_mod_event
  buradan re-export edilir — chat.py ve auction_service.py gibi henüz
  refactor edilmemiş modüllerin `from app.routers.moderation import ...`
  importları çalışmaya devam eder.
"""
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user
from app.services.moderation_service import (
    ModerationService,
    # ── Geriye dönük uyumluluk re-exportları ────────────────────────────────
    mute_key,         # noqa: F401
    kick_key,         # noqa: F401
    mod_key,          # noqa: F401
    MOD_CHANNEL,      # noqa: F401
    publish_mod_event,  # noqa: F401
)

router = APIRouter(prefix="/api/moderation", tags=["moderation"])


# ── Request şeması ───────────────────────────────────────────────────────────
class _TargetIn(BaseModel):
    username: str


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/{stream_id}/mute", status_code=status.HTTP_200_OK)
async def mute_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await ModerationService(db).mute(stream_id, body.username, current_user)


@router.post("/{stream_id}/unmute", status_code=status.HTTP_200_OK)
async def unmute_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await ModerationService(db).unmute(stream_id, body.username, current_user)


@router.post("/{stream_id}/kick", status_code=status.HTTP_200_OK)
async def kick_user(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await ModerationService(db).kick(stream_id, body.username, current_user)


@router.post("/{stream_id}/promote", status_code=status.HTTP_200_OK)
async def promote_moderator(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """İzleyiciyi Co-Host (moderatör) olarak atar. Sadece yayının asıl host'u çağırabilir."""
    return await ModerationService(db).promote(stream_id, body.username, current_user)


@router.post("/{stream_id}/demote", status_code=status.HTTP_200_OK)
async def demote_moderator(
    stream_id: int,
    body: _TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Kullanıcının moderatörlüğünü geri alır. Sadece yayının asıl host'u çağırabilir."""
    return await ModerationService(db).demote(stream_id, body.username, current_user)


@router.get("/{stream_id}/mods", status_code=status.HTTP_200_OK)
async def list_mods(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Aktif moderatör listesini döndürür (tüm kimliği doğrulanmış izleyiciler görebilir)."""
    return await ModerationService(db).list_mods(stream_id, current_user)


@router.get("/{stream_id}/status", status_code=status.HTTP_200_OK)
async def mod_status(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Host için mevcut mute/kick/mods listelerini döndürür."""
    return await ModerationService(db).get_status(stream_id, current_user)
