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
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut, SwipeLiveConfig
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.services.stream_service import StreamService
from app.services.like_service import LikeService
from app.services.swipe_live_service import get_swipe_live_config

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

@router.get("/{stream_id}/check")
async def check_stream_active(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Yayının hâlâ aktif olup olmadığını kontrol eder."""
    result = await db.execute(
        select(LiveStream).where(LiveStream.id == stream_id)
    )
    stream = result.scalar_one_or_none()
    return {"active": stream is not None and stream.ended_at is None}


@router.get("/{stream_id}/audience-insights")
async def audience_insights(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Pro yayıncıya özel: canlı yayındaki izleyicilerin bütçe segmentasyonu.
    Sadece yayın sahibi erişebilir.

    Segmentler:
      - Yüksek bütçe: max_budget >= 1000 TL
      - Orta bütçe: 250–999 TL
      - Düşük bütçe: < 250 TL
    """
    from app.core.exceptions import ForbiddenException, NotFoundException
    from app.utils.redis_client import get_redis
    from sqlalchemy import text as sql_text

    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if not stream:
        raise NotFoundException("Yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise ForbiddenException("Bu yayının istatistiklerine erişim yetkiniz yok")

    redis = await get_redis()
    # viewer_set kullanıcı adı ile, pip_viewer_set user_id ile saklar; her ikisini de çek
    chat_members_raw = await redis.smembers(f"live:viewer_set:{stream.room_name}")
    pip_members_raw = await redis.smembers(f"live:pip_viewer_set:{stream_id}")

    # chat_viewer_set içindeki username'leri user_id'ye çevir
    viewer_ids: set[int] = set()
    if chat_members_raw:
        usernames = [v.decode() if isinstance(v, bytes) else v for v in chat_members_raw]
        rows_uname = await db.execute(
            sql_text("SELECT id FROM users WHERE username = ANY(:names)"),
            {"names": usernames},
        )
        for r in rows_uname.fetchall():
            viewer_ids.add(r.id)

    # pip_viewer_set'teki integer user_id'leri ekle
    for v in (pip_members_raw or []):
        try:
            viewer_ids.add(int(v.decode() if isinstance(v, bytes) else v))
        except (ValueError, TypeError):
            pass

    if not viewer_ids:
        return {
            "viewer_count": stream.viewer_count,
            "avg_budget": None,
            "high_value_count": 0,
            "medium_value_count": 0,
            "low_budget_count": 0,
            "ready_buyers_count": 0,
            "segments": [
                {"label": "Yüksek Bütçe (1000₺+)", "count": 0, "color": "#4CAF50"},
                {"label": "Orta Bütçe (250-999₺)", "count": 0, "color": "#2196F3"},
                {"label": "Düşük Bütçe (<250₺)", "count": 0, "color": "#FF9800"},
            ],
        }

    rows = await db.execute(
        sql_text("SELECT id, max_budget, is_premium FROM users WHERE id = ANY(:ids) AND is_active = TRUE"),
        {"ids": list(viewer_ids)},
    )
    user_data = rows.fetchall()
    budgets = [float(r.max_budget) for r in user_data if r.max_budget is not None]
    avg_budget = round(sum(budgets) / len(budgets), 2) if budgets else None
    high_value = sum(1 for b in budgets if b >= 1000)
    medium_value = sum(1 for b in budgets if 250 <= b < 1000)
    low_budget = sum(1 for b in budgets if b < 250)
    ready_buyers = sum(1 for r in user_data if r.is_premium)

    pip_count = len(pip_members_raw) if pip_members_raw else 0
    return {
        "viewer_count": stream.viewer_count + pip_count,
        "avg_budget": avg_budget,
        "high_value_count": high_value,
        "medium_value_count": medium_value,
        "low_budget_count": low_budget,
        "ready_buyers_count": ready_buyers,
        "segments": [
            {"label": "Yüksek Bütçe (1000₺+)", "count": high_value, "color": "#4CAF50"},
            {"label": "Orta Bütçe (250-999₺)", "count": medium_value, "color": "#2196F3"},
            {"label": "Düşük Bütçe (<250₺)", "count": low_budget, "color": "#FF9800"},
        ],
    }


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


@router.post("/{stream_id}/pip-enter", status_code=status.HTTP_204_NO_CONTENT)
async def pip_enter(
    stream_id: int,
    current_user: User = Depends(get_current_user),
):
    """PiP moduna girildiğinde izleyiciyi pip_viewer_set'e ekle (2 saat TTL)."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    key = f"live:pip_viewer_set:{stream_id}"
    await redis.sadd(key, str(current_user.id))
    await redis.expire(key, 7200)


@router.delete("/{stream_id}/pip-exit", status_code=status.HTTP_204_NO_CONTENT)
async def pip_exit(
    stream_id: int,
    current_user: User = Depends(get_current_user),
):
    """PiP kapatıldığında izleyiciyi pip_viewer_set'ten çıkar."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.srem(f"live:pip_viewer_set:{stream_id}", str(current_user.id))


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


@router.get("/swipe-live-config", response_model=SwipeLiveConfig)
async def swipe_live_config(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    SwipeLive başlangıcı için kişiselleştirilmiş konfigürasyon.
    Yayınları kullanıcı ilgi + ClickHouse davranış skoruna göre sıralar,
    listings_per_group ve tercih edilen ilan kategorilerini döndürür.
    """
    return await get_swipe_live_config(current_user.id, db)


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
    current_user: User = Depends(get_current_user),
):
    """
    Yayın biterken izleyicilere önerilen diğer aktif yayınlar (Raid/Baskın).

    - Biten yayını (stream_id) sonuçlardan dışlar
    - Sıralama: kullanıcı kategori ilgisi (0.55) + hype_score (0.30) + viewer_count (0.15)
    - Maksimum 3 yayın döner
    """
    import math
    from app.core.hype_manager import hype_manager
    from app.services.feed_service import get_user_interests
    from app.utils.redis_client import get_redis

    result = await db.execute(
        select(LiveStream)
        .where(LiveStream.is_live == True, LiveStream.id != stream_id)  # noqa: E712
    )
    streams = result.scalars().all()

    if not streams:
        return []

    # Kullanıcı kategori ilgi skorları (kişiselleştirme)
    interests: dict[str, float] = await get_user_interests(current_user.id, db)

    # Redis'ten anlık izleyici sayılarını çek
    redis = await get_redis()
    viewer_keys = [f"live:viewers:{s.room_name}" for s in streams]
    raw_counts = await redis.mget(*viewer_keys) if viewer_keys else []
    viewer_map: dict[int, int] = {}
    for s, raw in zip(streams, raw_counts):
        viewer_map[s.id] = int(raw) if raw else s.viewer_count

    def _score(s: LiveStream) -> float:
        affinity = min(interests.get(s.category or "", 0.05), 1.0)
        hype = min(hype_manager.get_score(s.id) / 100.0, 1.0)
        viewers = math.log1p(viewer_map.get(s.id, 0)) / 10.0
        return affinity * 0.55 + hype * 0.30 + viewers * 0.15

    top3 = sorted(streams, key=_score, reverse=True)[:3]

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
