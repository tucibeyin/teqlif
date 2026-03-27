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
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.security.captcha import verify_captcha_token
from app.services.stream_service import StreamService

router = APIRouter(prefix="/api/streams", tags=["streams"])


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
    _captcha: None = Depends(verify_captcha_token),
):
    return await StreamService(db).start(data, current_user, background_tasks)


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


@router.get("/following/live", response_model=list[StreamOut])
async def get_followed_live_streams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await StreamService(db).get_followed_live_streams(current_user.id)


@router.get("/active", response_model=list[StreamOut])
async def get_active_streams(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await StreamService(db).get_active_streams(current_user_id)
