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

from fastapi import APIRouter, Depends, Query, UploadFile, File, status, BackgroundTasks
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut, SwipeLiveConfig
from app.utils.auth import get_current_user, bearer_scheme, decode_token

from app.services.like_service import LikeService
from app.use_cases.feed.queries.swipe_live_queries import SwipeLiveQueries
from app.core.uow import SqlAlchemyUnitOfWork

from app.use_cases.streams.commands.start_stream import StartStreamCommand
from app.use_cases.streams.commands.join_stream import JoinStreamCommand
from app.use_cases.streams.commands.lifecycle_commands import ConfirmLiveCommand, CancelPendingStreamCommand
from app.use_cases.streams.commands.misc_commands import EndStreamCommand, UpdateThumbnailCommand
from app.use_cases.streams.commands.cohost_commands import InviteCohostCommand, AcceptCohostInviteCommand, RemoveCohostCommand, LeaveCohostCommand
from app.use_cases.streams.queries.get_viewers import GetViewersQuery
from app.use_cases.streams.queries.misc_queries import GetFollowedLiveStreamsQuery, GetActiveStreamsQuery

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

@router.get("/my-history")
async def get_my_stream_history(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = 20,
    cursor: str | None = None
):
    """Kullanıcının geçmiş yayınlarını listeler (ended_at is not null)"""
    from app.models.auction import Auction
    from sqlalchemy import func
    
    # Yayınları al
    query = (
        select(LiveStream)
        .where(LiveStream.host_id == current_user.id)
        .where(LiveStream.ended_at.is_not(None))
    )
    if cursor:
        from datetime import datetime
        cursor_dt = datetime.fromisoformat(cursor.replace(' ', '+'))
        query = query.where(LiveStream.started_at < cursor_dt)

    query = (
        query.order_by(LiveStream.started_at.desc())
        .limit(limit)
    )
    result = await db.execute(query)
    streams = result.scalars().all()
    
    # Her yayın için ciro (revenue) topla
    stream_ids = [s.id for s in streams]
    revenues = {}
    if stream_ids:
        rev_query = (
            select(Auction.stream_id, func.sum(Auction.final_price))
            .where(Auction.stream_id.in_(stream_ids))
            .where(Auction.winner_username.is_not(None))
            .group_by(Auction.stream_id)
        )
        rev_result = await db.execute(rev_query)
        for row in rev_result.all():
            revenues[row[0]] = float(row[1] or 0.0)
            
    out = []
    for s in streams:
        out.append({
            "id": s.id,
            "title": s.title,
            "category": s.category,
            "started_at": s.started_at,
            "ended_at": s.ended_at,
            "viewer_count": s.viewer_count,
            "revenue": revenues.get(s.id, 0.0)
        })
        
    return out

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
        sql_text("SELECT id, max_budget, is_premium FROM users WHERE id = ANY(:ids) AND status = 'active'"),
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
    from app.use_cases.streams.commands.start_stream import StartStreamCommand
    from app.core.uow import SqlAlchemyUnitOfWork
    
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = StartStreamCommand(uow)
    return await cmd.execute(
        user_id=current_user.id,
        title=data.title,
        category=data.category,
        listing_id=getattr(data, "listing_id", None),
        thumbnail_url=getattr(data, "thumbnail_url", None)
    )


@router.post("/{stream_id}/confirm-live", status_code=status.HTTP_200_OK)
async def confirm_live(
    stream_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await ConfirmLiveCommand(uow).execute(stream_id, current_user, background_tasks)


@router.delete("/{stream_id}/cancel", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    await CancelPendingStreamCommand(uow).execute(stream_id, current_user)


@router.post("/{stream_id}/end", status_code=status.HTTP_200_OK)
async def end_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await EndStreamCommand(uow).execute(stream_id, current_user)


@router.get("/{stream_id}/viewers")
async def get_viewers(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await GetViewersQuery(uow).execute(stream_id, current_user)


@router.post("/{stream_id}/join", response_model=JoinTokenOut)
async def join_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await JoinStreamCommand(uow).execute(stream_id, current_user)


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
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await UpdateThumbnailCommand(uow).execute(stream_id, current_user, file)


@router.post("/{stream_id}/cohost/invite", status_code=status.HTTP_200_OK)
async def invite_cohost(
    stream_id: int,
    body: _CohostTargetBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await InviteCohostCommand(uow).execute(stream_id, body.target_username, current_user)


@router.post("/{stream_id}/cohost/accept", response_model=StreamTokenOut)
async def accept_cohost(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await AcceptCohostInviteCommand(uow).execute(stream_id, current_user)


@router.post("/{stream_id}/cohost/remove", status_code=status.HTTP_200_OK)
async def remove_cohost(
    stream_id: int,
    body: _CohostTargetBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await RemoveCohostCommand(uow).execute(stream_id, body.target_username, current_user)


@router.post("/{stream_id}/cohost/leave", status_code=status.HTTP_200_OK)
async def leave_cohost(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    return await LeaveCohostCommand(uow).execute(stream_id, current_user)


@router.get("/suggested-streamers")
async def get_suggested_streamers(
    limit: int = Query(default=15, ge=1, le=30),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Son 90 günde yayın yapmış kullanıcıları kişiselleştirilmiş skorla sıralar.

    Skor bileşenleri (toplam 1.0):
      - Şu an canlı yayında        → +0.35 bonus (sabit)
      - Kategori affinity bonusu   → 0.25  (user_interests'ten top-3 kategori eşleşmesi)
      - Ortalama izleyici          → 0.25  (LOG normalize, platforma göre kalibre)
      - Takipçi sayısı             → 0.15  (LOG normalize)
      - Yayın sıklığı              → 0.10  (LOG normalize)

    Önce takip edilmeyenler (yeni keşif), veri yoksa takip edilenler dahil edilir.
    """
    from sqlalchemy import text as sa_text

    # Kullanıcının top-3 ilgi kategorisini çek
    interest_result = await db.execute(
        sa_text("""
            SELECT category FROM user_interests
            WHERE user_id = :uid
            ORDER BY score DESC
            LIMIT 3
        """),
        {"uid": current_user.id},
    )
    top_cats = [r[0] for r in interest_result.fetchall()]
    # PostgreSQL ANY() için array literal
    cats_literal = "ARRAY[" + ",".join(f"'{c}'" for c in top_cats) + "]" if top_cats else "ARRAY[]::text[]"

    base_query = f"""
        WITH streamer_stats AS (
            SELECT
                u.id,
                u.username,
                u.full_name,
                u.profile_image_url,
                (u.email_verified AND u.phone_verified) AS is_verified,
                u.is_premium,
                COUNT(ls.id)                                    AS stream_count,
                COALESCE(AVG(ls.viewer_count), 0)               AS avg_viewers,
                COALESCE(fol.follower_count, 0)                 AS follower_count,
                -- Şu an canlı mı? (ended_at IS NULL = aktif yayın)
                COALESCE(live_now.is_live, FALSE)               AS is_live,
                -- Kullanıcının ilgi kategorileriyle eşleşme
                COALESCE(cat_match.has_match, FALSE)            AS category_match
            FROM users u
            INNER JOIN live_streams ls ON ls.host_id = u.id
                AND ls.started_at >= NOW() - INTERVAL '90 days'
            LEFT JOIN (
                SELECT followed_id, COUNT(*) AS follower_count
                FROM follows GROUP BY followed_id
            ) fol ON fol.followed_id = u.id
            LEFT JOIN (
                SELECT DISTINCT host_id, TRUE AS is_live
                FROM live_streams
                WHERE ended_at IS NULL
            ) live_now ON live_now.host_id = u.id
            LEFT JOIN (
                SELECT DISTINCT host_id, TRUE AS has_match
                FROM live_streams
                WHERE started_at >= NOW() - INTERVAL '90 days'
                  AND category = ANY({cats_literal})
            ) cat_match ON cat_match.host_id = u.id
            WHERE u.id != :uid
              AND u.status = 'active'
              AND u.id NOT IN (
                  SELECT blocked_id FROM user_blocks WHERE blocker_id = :uid
                  UNION
                  SELECT blocker_id FROM user_blocks WHERE blocked_id = :uid
              )
            {{follow_filter}}
            GROUP BY u.id, u.username, u.full_name, u.profile_image_url,
                     u.email_verified, u.phone_verified, u.is_premium, fol.follower_count,
                     live_now.is_live, cat_match.has_match
            HAVING COUNT(ls.id) >= 1
        )
        SELECT
            id, username, full_name, profile_image_url,
            is_verified, is_premium, stream_count, avg_viewers, follower_count, is_live,
            -- Kişiselleştirilmiş kompozit skor
            (
                CASE WHEN is_live THEN 0.35 ELSE 0.0 END
                + CASE WHEN category_match THEN 0.25 ELSE 0.0 END
                + LEAST(LOG(1.0 + avg_viewers) / LOG(51.0), 1.0) * 0.25
                + LEAST(LOG(1.0 + follower_count) / LOG(1001.0), 1.0) * 0.15
                + LEAST(LOG(1.0 + stream_count) / LOG(21.0), 1.0) * 0.10
            ) AS score
        FROM streamer_stats
        ORDER BY score DESC, stream_count DESC
        LIMIT :lim
    """

    result = await db.execute(
        sa_text(base_query.format(
            follow_filter="AND u.id NOT IN (SELECT followed_id FROM follows WHERE follower_id = :uid)"
        )),
        {"uid": current_user.id, "lim": limit},
    )
    rows = result.fetchall()

    if not rows:
        result = await db.execute(
            sa_text(base_query.format(follow_filter="")),
            {"uid": current_user.id, "lim": limit},
        )
        rows = result.fetchall()

    return [
        {
            "id": row[0],
            "username": row[1],
            "full_name": row[2],
            "profile_image_url": row[3],
            "is_verified": row[4],
            "is_premium": row[5],
            "stream_count": int(row[6]),
            "avg_viewers": round(float(row[7]), 1),
            "follower_count": int(row[8]),
            "is_live": bool(row[9]),
        }
        for row in rows
    ]


@router.get("/following/live", response_model=list[StreamOut])
async def get_followed_live_streams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    uow.session = db
    return await GetFollowedLiveStreamsQuery(uow).execute(current_user.id)


@router.get("/recommended", response_model=list[StreamOut])
async def get_recommended_streams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Category affinity'ye göre kişiselleştirilmiş aktif yayınlar (max 8)."""
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    uow.session = db
    return await GetActiveStreamsQuery(uow).execute(current_user.id)


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
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    uow.session = db
    return await SwipeLiveQueries(uow).get_swipe_live_config(current_user.id)


@router.get("/active", response_model=list[StreamOut])
async def get_active_streams(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    uow.session = db
    return await GetActiveStreamsQuery(uow).execute(current_user_id)


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
