import Redis from "ioredis";

const globalForRedis = globalThis as unknown as {
    redis: Redis | undefined;
};

export const redis =
    globalForRedis.redis ??
    new Redis(process.env.REDIS_URL || "redis://localhost:6379", {
        maxRetriesPerRequest: 3,
        enableReadyCheck: false,
    });

if (process.env.NODE_ENV !== "production") globalForRedis.redis = redis;

/**
 * Executes an atomic Lua script to place a bid.
 * It checks if the new amount is greater than the current highest bid.
 * If yes, it updates the highest bid and adds the bid details to a list for later syncing.
 * 
 * @returns {number} 1 if bid accepted, 0 if rejected (too low)
 */
export async function placeLiveBid(roomId: string, userId: string, amount: number): Promise<number> {
    const highestBidKey = `highest_bid:${roomId}`;
    const bidsListKey = `bids:${roomId}`;
    const timestamp = Date.now();

    // LUA Script:
    // KEYS[1] = highestBidKey
    // KEYS[2] = bidsListKey
    // ARGV[1] = amount
    // ARGV[2] = userId
    // ARGV[3] = timestamp
    const script = `
        local currentHighest = tonumber(redis.call("GET", KEYS[1]) or "0")
        local newAmount = tonumber(ARGV[1])
        
        if newAmount > currentHighest then
            redis.call("SET", KEYS[1], newAmount)
            local bidData = '{"userId":"' .. ARGV[2] .. '","amount":' .. newAmount .. ',"timestamp":' .. ARGV[3] .. '}'
            redis.call("RPUSH", KEYS[2], bidData)
            return 1
        else
            return 0
        end
    `;

    const result = await redis.eval(script, 2, highestBidKey, bidsListKey, amount.toString(), userId, timestamp.toString());
    return result as number;
}

/**
 * Fetches all bids for a room from Redis and clears the list.
 */
export async function getAndClearRoomBids(roomId: string) {
    const bidsListKey = `bids:${roomId}`;

    // Get all items and then delete the key atomically using MULTI/EXEC
    const result = await redis.multi()
        .lrange(bidsListKey, 0, -1)
        .del(bidsListKey)
        .exec();

    if (!result || !result[0] || result[0][0]) {
        return [];
    }

    const rawBids = result[0][1] as string[];
    return rawBids.map(b => JSON.parse(b));
}

export default redis;
