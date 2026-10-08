from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class GetMyRecordingsQuery:
    """Host'un son 30 günlük kayıtlarını döner."""

    _ACTIVE_STATUSES = ("recording", "encoding", "encoded", "available", "expired")

    def __init__(self, db: AsyncSession):
        self._db = db

    async def execute(self, host_id: int) -> list[dict]:
        rows = (await self._db.execute(text("""
            SELECT
                sr.id            AS recording_id,
                sr.stream_id,
                ls.title         AS stream_title,
                sr.status,
                sr.duration_secs,
                sr.encoded_size_bytes,
                sr.available_at,
                sr.expires_at,
                sr.recording_started_at
            FROM stream_recordings sr
            JOIN live_streams ls ON ls.id = sr.stream_id
            WHERE sr.host_id = :host_id
              AND sr.status = ANY(:statuses)
              AND sr.recording_started_at > NOW() - INTERVAL '30 days'
            ORDER BY sr.recording_started_at DESC
        """), {
            "host_id": host_id,
            "statuses": list(self._ACTIVE_STATUSES),
        })).mappings().all()

        return [dict(r) for r in rows]
