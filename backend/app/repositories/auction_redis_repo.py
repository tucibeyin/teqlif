"""
Auction Redis Repository — Açık artırma state yönetimi ve atomik Redis/Lua script işlemlerini izole eder.
"""

from app.utils.redis_client import get_redis
from app.services.moderation_service import mute_key, mod_key
from typing import Dict, Any, List, Optional, Tuple

def auction_key(stream_id: int) -> str:
    return f"auction:{stream_id}"

# ── Lua scriptleri ───────────────────────────────────────────────────────────

# Sadece okuma — Redis'te hiçbir şey değiştirmez.
_VALIDATE_BID_SCRIPT = """
local key = KEYS[1]
local amount = tonumber(ARGV[1])
local status = redis.call('hget', key, 'status')
if status ~= 'active' then return {0, 'not_active'} end
local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
local bid_count = tonumber(redis.call('hget', key, 'bid_count')) or 0

if bid_count == 0 then
    if amount < current then return {0, 'too_low'} end
else
    local increment = 1
    if current >= 1000 then increment = 50
    elseif current >= 500 then increment = 25
    elseif current >= 100 then increment = 10 end

    if amount < current + increment then return {0, 'too_low'} end
end

return {1, tostring(current)}
"""

_BID_SCRIPT = """
local key = KEYS[1]
local amount = tonumber(ARGV[1])
local bidder_id = ARGV[2]
local bidder_name = ARGV[3]
local status = redis.call('hget', key, 'status')
if status ~= 'active' then return {0, 'not_active'} end

local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
local bid_count = tonumber(redis.call('hget', key, 'bid_count')) or 0

if bid_count == 0 then
    if amount < current then return {0, 'too_low'} end
else
    local increment = 1
    if current >= 1000 then increment = 50
    elseif current >= 500 then increment = 25
    elseif current >= 100 then increment = 10 end

    if amount < current + increment then return {0, 'too_low'} end
end

redis.call('hset', key,
    'current_bid', tostring(amount),
    'current_bidder_id', bidder_id,
    'current_bidder_name', bidder_name)
redis.call('hincrby', key, 'bid_count', 1)
return {1, tostring(amount)}
"""

_BUY_IT_NOW_REQUEST_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'active' and status ~= 'paused' then
    return {0, 'not_active'}
end
local bin_raw = redis.call('hget', key, 'buy_it_now_price')
if not bin_raw or bin_raw == '' then
    return {0, 'no_bin_price'}
end
local bin = tonumber(bin_raw)
local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
if current >= bin then
    return {0, 'bid_exceeds_bin'}
end
redis.call('hset', key, 'pre_pending_status', status)
redis.call('hset', key, 'status', 'buy_it_now_pending')
redis.call('hset', key, 'bin_buyer_id', ARGV[1])
redis.call('hset', key, 'bin_buyer_username', ARGV[2])
return {1, bin_raw}
"""

_BUY_IT_NOW_ACCEPT_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'buy_it_now_pending' then
    return {0, 'not_pending'}
end
local bin_raw = redis.call('hget', key, 'buy_it_now_price')
if not bin_raw or bin_raw == '' then
    return {0, 'no_bin_price'}
end
local buyer_id = redis.call('hget', key, 'bin_buyer_id') or ''
local buyer_username = redis.call('hget', key, 'bin_buyer_username') or ''
redis.call('hset', key, 'status', 'buy_it_now_locked')
return {1, bin_raw, buyer_id, buyer_username}
"""

_BUY_IT_NOW_REJECT_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'buy_it_now_pending' then
    return {0, 'not_pending'}
end
local prev = redis.call('hget', key, 'pre_pending_status') or 'active'
local buyer_username = redis.call('hget', key, 'bin_buyer_username') or ''
local buyer_id = redis.call('hget', key, 'bin_buyer_id') or ''
redis.call('hset', key, 'status', prev)
redis.call('hdel', key, 'bin_buyer_id', 'bin_buyer_username', 'pre_pending_status')
return {1, prev, buyer_username, buyer_id}
"""


class AuctionRedisRepository:
    def __init__(self):
        # Redis instance is fetched asynchronously
        pass

    async def get_state(self, stream_id: int) -> Dict[str, str]:
        redis = await get_redis()
        return await redis.hgetall(auction_key(stream_id))

    async def get_status(self, stream_id: int) -> Optional[str]:
        redis = await get_redis()
        return await redis.hget(auction_key(stream_id), "status")

    async def set_state(self, stream_id: int, mapping: dict, ttl: int = 86400) -> None:
        redis = await get_redis()
        key = auction_key(stream_id)
        await redis.hset(key, mapping=mapping)
        if ttl:
            await redis.expire(key, ttl)

    async def set_status(self, stream_id: int, status: str) -> None:
        redis = await get_redis()
        await redis.hset(auction_key(stream_id), "status", status)

    async def delete_auction(self, stream_id: int) -> List[str]:
        redis = await get_redis()
        _bidder_set_key = f"auction:bidders:{stream_id}"
        bidders = await redis.smembers(_bidder_set_key)
        await redis.delete(_bidder_set_key)
        await redis.delete(auction_key(stream_id))
        return list(bidders)

    async def is_user_muted(self, stream_id: int, user_id: int) -> bool:
        redis = await get_redis()
        return await redis.sismember(mute_key(stream_id), str(user_id))

    async def is_user_mod(self, stream_id: int, user_id: int) -> bool:
        redis = await get_redis()
        return await redis.sismember(mod_key(stream_id), str(user_id))

    async def add_bidder(self, stream_id: int, user_id: int, ttl: int = 86400) -> None:
        redis = await get_redis()
        bidder_key = f"auction:bidders:{stream_id}"
        await redis.sadd(bidder_key, str(user_id))
        await redis.expire(bidder_key, ttl)

    # ── Lua Script Executions ────────────────────────────────────────────────
    
    async def validate_bid(self, stream_id: int, amount: float) -> Tuple[int, str]:
        redis = await get_redis()
        val = await redis.eval(_VALIDATE_BID_SCRIPT, 1, auction_key(stream_id), str(amount))
        return int(val[0]), val[1]

    async def execute_bid(self, stream_id: int, amount: float, user_id: int, username: str) -> Tuple[int, str]:
        redis = await get_redis()
        val = await redis.eval(_BID_SCRIPT, 1, auction_key(stream_id), str(amount), str(user_id), username)
        return int(val[0]), val[1]

    async def request_buy_it_now(self, stream_id: int, user_id: int, username: str) -> Tuple[int, str]:
        redis = await get_redis()
        val = await redis.eval(_BUY_IT_NOW_REQUEST_SCRIPT, 1, auction_key(stream_id), str(user_id), username)
        return int(val[0]), val[1]

    async def accept_buy_it_now(self, stream_id: int) -> Tuple[int, str, str, str]:
        redis = await get_redis()
        val = await redis.eval(_BUY_IT_NOW_ACCEPT_SCRIPT, 1, auction_key(stream_id))
        if int(val[0]) == 0:
            return int(val[0]), val[1], "", ""
        return int(val[0]), val[1], val[2], val[3]

    async def reject_buy_it_now(self, stream_id: int) -> Tuple[int, str, str, str]:
        redis = await get_redis()
        val = await redis.eval(_BUY_IT_NOW_REJECT_SCRIPT, 1, auction_key(stream_id))
        if int(val[0]) == 0:
            return int(val[0]), val[1], "", ""
        return int(val[0]), val[1], val[2], val[3]

    async def has_cooldown(self, stream_id: int, user_id: int) -> bool:
        redis = await get_redis()
        val = await redis.get(f"bin_cooldown:{stream_id}:{user_id}")
        return bool(val)

    async def set_cooldown(self, stream_id: int, user_id: int, ttl: int = 60) -> None:
        redis = await get_redis()
        await redis.set(f"bin_cooldown:{stream_id}:{user_id}", "1", ex=ttl)

    async def update_bid_state(self, stream_id: int, current_bid: str, bidder_id: str, bidder_name: str) -> None:
        redis = await get_redis()
        await redis.hset(auction_key(stream_id), mapping={
            "current_bid": current_bid,
            "current_bidder_id": bidder_id,
            "current_bidder_name": bidder_name,
        })
