from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.stream import LiveStream
from app.models.user import User
from app.models.follow import Follow
from app.use_cases.streams.stream_utils import _fill_viewer_counts, _apply_block_filter
from app.services.like_service import LikeService

class GetFollowedLiveStreamsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user_id: int) -> list:
        query = (
            select(LiveStream)
            .join(Follow, Follow.followed_id == LiveStream.host_id)
            .where(
                Follow.follower_id == current_user_id,
                LiveStream.is_live == True,
            )
            .order_by(LiveStream.started_at.desc())
        )
        result = await self.uow.session.execute(query)
        streams = result.scalars().all()

        await _fill_viewer_counts(streams, tag=f"followed user_id={current_user_id}")

        stream_ids = [s.id for s in streams]
        like_counts = await LikeService.batch_stream_likes(self.uow.session, stream_ids)
        for stream in streams:
            stream.likes_count = like_counts.get(stream.id, 0)

        return streams

class GetActiveStreamsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user_id: int) -> list:
        query = (
            select(LiveStream)
            .where(LiveStream.is_live == True)
            .order_by(LiveStream.started_at.desc())
            .limit(100)
        )
        if current_user_id:
            query = _apply_block_filter(query, LiveStream.host_id, current_user_id)
        
        result = await self.uow.session.execute(query)
        streams = result.scalars().all()

        await _fill_viewer_counts(streams, tag="active_streams")
        
        stream_ids = [s.id for s in streams]
        like_counts = await LikeService.batch_stream_likes(self.uow.session, stream_ids)
        for stream in streams:
            stream.likes_count = like_counts.get(stream.id, 0)
            
        return streams
