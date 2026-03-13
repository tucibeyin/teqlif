import uuid
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from livekit.api import AccessToken, VideoGrants

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut
from app.utils.auth import get_current_user
from app.utils.redis_client import get_redis
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/streams", tags=["streams"])

VIEWER_TTL = 8 * 3600  # 8 saat


def _make_token(room_name: str, user: User, can_publish: bool) -> str:
    grant = VideoGrants(
        room_join=True,
        room=room_name,
        can_publish=can_publish,
        can_subscribe=True,
        can_publish_data=can_publish,
    )
    token = (
        AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
        .with_identity(str(user.id))
        .with_name(user.username)
        .with_grants(grant)
    )
    return token.to_jwt()


@router.post("/start", response_model=StreamTokenOut, status_code=status.HTTP_201_CREATED)
async def start_stream(
    data: StreamStart,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Kullanıcının aktif yayını var mı?
    result = await db.execute(
        select(LiveStream).where(
            LiveStream.host_id == current_user.id,
            LiveStream.is_live == True,  # noqa: E712
        )
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Zaten aktif bir yayınınız var")

    room_name = f"stream_{current_user.id}_{uuid.uuid4().hex[:8]}"

    stream = LiveStream(
        room_name=room_name,
        title=data.title,
        host_id=current_user.id,
    )
    db.add(stream)
    await db.commit()
    await db.refresh(stream)

    token = _make_token(room_name, current_user, can_publish=True)

    return StreamTokenOut(
        stream_id=stream.id,
        room_name=room_name,
        livekit_url=settings.livekit_url,
        token=token,
    )


@router.post("/{stream_id}/end", status_code=status.HTTP_200_OK)
async def end_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()

    if not stream:
        raise HTTPException(status_code=404, detail="Yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise HTTPException(status_code=403, detail="Bu yayını sonlandırma yetkiniz yok")
    if not stream.is_live:
        raise HTTPException(status_code=400, detail="Yayın zaten sonlanmış")

    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)
    await db.commit()

    # Redis viewer count temizle
    redis = await get_redis()
    await redis.delete(f"live:viewers:{stream.room_name}")

    return {"message": "Yayın sonlandırıldı"}


@router.post("/{stream_id}/join", response_model=JoinTokenOut)
async def join_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(LiveStream).where(LiveStream.id == stream_id)
    )
    stream = result.scalar_one_or_none()

    if not stream or not stream.is_live:
        raise HTTPException(status_code=404, detail="Aktif yayın bulunamadı")

    # Host kendi yayınına izleyici olarak katılamaz
    if stream.host_id == current_user.id:
        raise HTTPException(status_code=400, detail="Kendi yayınınıza izleyici olarak katılamazsınız")

    # Redis'te viewer sayısını artır
    redis = await get_redis()
    viewer_key = f"live:viewers:{stream.room_name}"
    await redis.incr(viewer_key)
    await redis.expire(viewer_key, VIEWER_TTL)

    token = _make_token(stream.room_name, current_user, can_publish=False)

    return JoinTokenOut(
        stream_id=stream.id,
        room_name=stream.room_name,
        livekit_url=settings.livekit_url,
        token=token,
        title=stream.title,
        host_username=stream.host.username,
    )


@router.delete("/{stream_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()

    if stream:
        redis = await get_redis()
        viewer_key = f"live:viewers:{stream.room_name}"
        count = await redis.decr(viewer_key)
        if count < 0:
            await redis.set(viewer_key, 0)


@router.get("/active", response_model=list[StreamOut])
async def get_active_streams(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LiveStream).where(LiveStream.is_live == True)  # noqa: E712
        .order_by(LiveStream.started_at.desc())
    )
    streams = result.scalars().all()

    redis = await get_redis()
    for stream in streams:
        try:
            count = await redis.get(f"live:viewers:{stream.room_name}")
            stream.viewer_count = int(count) if count else 0
        except Exception:
            pass

    return streams
