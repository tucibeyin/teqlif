"""
Canlı yayın router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db, background_tasks) alır
  2. StreamService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, LiveKit token üretimi ve Redis işlemleri tamamen
app.services.stream_service.StreamService'e taşınmıştır.
"""
from typing import Optional

from fastapi import APIRouter, Depends, UploadFile, File, status, BackgroundTasks
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.services.stream_service import StreamService
from app.services.like_service import LikeService

router = APIRouter(prefix="/api/streams", tags=["streams"])


class _CohostTargetBody(BaseModel):
    target_username: str


# ── Opsiyonel token çözümleyici (unauthenticated erişim için) ────────────────
async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/start", response_model=StreamTokenOut, status_code=status.HTTP_201_CREATED)
async def start_stream(
    data: StreamStart,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).start(data, current_user, background_tasks)


@router.post("/{stream_id}/confirm-live", status_code=status.HTTP_200_OK)
async def confirm_live(
    stream_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).confirm_live(stream_id, current_user, background_tasks)


@router.delete("/{stream_id}/cancel", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await StreamService(db).cancel_pending(stream_id, current_user)


@router.post("/{stream_id}/end", status_code=status.HTTP_200_OK)
async def end_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).end(stream_id, current_user)


@router.get("/{stream_id}/viewers")
async def get_viewers(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).get_viewers(stream_id, current_user)


@router.post("/{stream_id}/join", response_model=JoinTokenOut)
async def join_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).join(stream_id, current_user)


@router.post("/{stream_id}/like", status_code=status.HTTP_200_OK)
async def like_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Canlı yayına kalp gönder (add-only, toggle yok).
    Aynı yayına art arda birden fazla kez çağrılabilir.
    Tüm izleyicilere WebSocket ile `stream_like` sinyali yayımlanır.
    """
    return await LikeService(db).add_stream_like(stream_id, current_user.id, current_user.username)


@router.delete("/{stream_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.core.logger import get_logger
    get_logger(__name__).info(
        "[STREAMS] Yayından ayrılındı | stream_id=%s user_id=%s", stream_id, current_user.id
    )


@router.patch("/{stream_id}/thumbnail")
async def update_thumbnail(
    stream_id: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).update_thumbnail(stream_id, current_user, file)


@router.post("/{stream_id}/cohost/invite", status_code=status.HTTP_200_OK)
async def invite_cohost(
    stream_id: int,
    body: _CohostTargetBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).invite_cohost(stream_id, body.target_username, current_user)


@router.post("/{stream_id}/cohost/accept", response_model=StreamTokenOut)
async def accept_cohost(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).accept_cohost_invite(stream_id, current_user)


@router.post("/{stream_id}/cohost/remove", status_code=status.HTTP_200_OK)
async def remove_cohost(
    stream_id: int,
    body: _CohostTargetBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).remove_cohost(stream_id, body.target_username, current_user)


@router.post("/{stream_id}/cohost/leave", status_code=status.HTTP_200_OK)
async def leave_cohost(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await StreamService(db).leave_cohost(stream_id, current_user)


@router.get("/following/live", response_model=list[StreamOut])
async def get_followed_live_streams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await StreamService(db).get_followed_live_streams(current_user.id)


@router.get("/recommended", response_model=list[StreamOut])
async def get_recommended_streams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Category affinity'ye göre kişiselleştirilmiş aktif yayınlar (max 8)."""
    return await StreamService(db).get_recommended_streams(current_user.id)


@router.get("/active", response_model=list[StreamOut])
async def get_active_streams(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await StreamService(db).get_active_streams(current_user_id)


@router.get("/{stream_id}/raid-targets")
async def get_raid_targets(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """
    Yayın biterken izleyicilere önerilen diğer aktif yayınlar (Raid/Baskın).

    - Biten yayını (stream_id) sonuçlardan dışlar
    - Sıralama: hype_score DESC → viewer_count DESC
    - Maksimum 3 yayın döner
    """
    from app.core.hype_manager import hype_manager
    from app.utils.redis_client import get_redis

    result = await db.execute(
        select(LiveStream)
        .where(LiveStream.is_live == True, LiveStream.id != stream_id)  # noqa: E712
    )
    streams = result.scalars().all()

    if not streams:
        return []

    # Redis'ten anlık izleyici sayılarını çek
    redis = await get_redis()
    viewer_keys = [f"live:viewers:{s.room_name}" for s in streams]
    raw_counts = await redis.mget(*viewer_keys) if viewer_keys else []
    viewer_map: dict[int, int] = {}
    for s, raw in zip(streams, raw_counts):
        viewer_map[s.id] = int(raw) if raw else s.viewer_count

    # Hype skoru + izleyici sayısına göre sırala
    def _sort_key(s: LiveStream) -> tuple:
        return (hype_manager.get_score(s.id), viewer_map.get(s.id, 0))

    top3 = sorted(streams, key=_sort_key, reverse=True)[:3]

    return [
        {
            "stream_id": s.id,
            "room_id": s.id,
            "room_name": s.room_name,
            "title": s.title,
            "host_name": s.host.username if s.host else "",
            "viewer_count": viewer_map.get(s.id, 0),
            "hype_score": round(hype_manager.get_score(s.id)),
            "thumbnail_url": s.thumbnail_url,
            "category": s.category,
        }
        for s in top3
    ]
