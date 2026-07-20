from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from app.utils.redis_client import get_redis
import json

INTEREST_CACHE_TTL = 900

async def get_user_interests(user_id: int, db: AsyncSession) -> dict[str, float]:
    redis = await get_redis()
    cache_key = f"interests:{user_id}"
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    rows = await db.execute(
        text("SELECT category, score FROM user_interests WHERE user_id = :uid ORDER BY score DESC"),
        {"uid": user_id},
    )
    interests = {row.category: row.score for row in rows}
    if interests:
        await redis.setex(cache_key, INTEREST_CACHE_TTL, json.dumps(interests))
    return interests
