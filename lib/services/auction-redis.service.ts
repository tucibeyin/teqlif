import { redis } from "@/lib/redis";

// ── Types ─────────────────────────────────────────────────────────────────────

export type AuctionStatus = "active" | "closed";

export interface AuctionState {
  status: AuctionStatus | null;
  highestBid: number;
  highestBidder: string | null;
}

export type BidResult =
  | { accepted: true; newHighestBid: number }
  | { accepted: false; reason: "auction_not_active" | "bid_too_low" };

// ── Key Helpers ───────────────────────────────────────────────────────────────

const keys = {
  status: (adId: string) => `auction:${adId}:status`,
  highestBid: (adId: string) => `auction:${adId}:highest_bid`,
  highestBidder: (adId: string) => `auction:${adId}:highest_bidder`,
} as const;

// ── Lua Script ────────────────────────────────────────────────────────────────

/**
 * Atomik teklif scripti. Race condition'ı Redis tek-thread garantisi ile engeller.
 *
 * KEYS[1] = auction:{adId}:status
 * KEYS[2] = auction:{adId}:highest_bid
 * KEYS[3] = auction:{adId}:highest_bidder
 *
 * ARGV[1] = bidAmount (integer string)
 * ARGV[2] = userId
 *
 * Dönüş değerleri:
 *   0 → açık artırma aktif değil
 *   1 → teklif reddedildi (mevcut fiyata eşit veya düşük)
 *   2 → teklif kabul edildi
 */
const PLACE_BID_SCRIPT = `
  local status = redis.call("GET", KEYS[1])
  if status ~= "active" then
    return 0
  end

  local current  = tonumber(redis.call("GET", KEYS[2])) or 0
  local incoming = tonumber(ARGV[1])

  if incoming > current then
    redis.call("SET", KEYS[2], incoming)
    redis.call("SET", KEYS[3], ARGV[2])
    return 2
  else
    return 1
  end
`;

// ── Service ───────────────────────────────────────────────────────────────────

/**
 * Açık artırmayı başlatır.
 * Status 'active' yapılır, isteğe bağlı başlangıç fiyatı set edilir,
 * önceki highest_bidder temizlenir.
 */
export async function startAuction(
  adId: string,
  startingBid: number = 0
): Promise<void> {
  const pipeline = redis.pipeline();
  pipeline.set(keys.status(adId), "active");
  pipeline.set(keys.highestBid(adId), startingBid);
  pipeline.del(keys.highestBidder(adId));
  await pipeline.exec();
}

/**
 * Lua script aracılığıyla atomik teklif işlemi gerçekleştirir.
 * Aynı anda gelen teklifler için Redis'in tek-thread modeli race condition'ı engeller.
 */
export async function placeBid(
  adId: string,
  userId: string,
  bidAmount: number
): Promise<BidResult> {
  const result = (await redis.eval(
    PLACE_BID_SCRIPT,
    3,
    keys.status(adId),
    keys.highestBid(adId),
    keys.highestBidder(adId),
    bidAmount.toString(),
    userId
  )) as number;

  if (result === 0) {
    return { accepted: false, reason: "auction_not_active" };
  }

  if (result === 1) {
    return { accepted: false, reason: "bid_too_low" };
  }

  return { accepted: true, newHighestBid: bidAmount };
}

/**
 * Açık artırmanın anlık durumunu döner.
 * Üç key'i tek MGET çağrısıyla okur (round-trip optimizasyonu).
 */
export async function getAuctionState(adId: string): Promise<AuctionState> {
  const [rawStatus, rawHighestBid, rawHighestBidder] = await redis.mget(
    keys.status(adId),
    keys.highestBid(adId),
    keys.highestBidder(adId)
  );

  return {
    status: (rawStatus as AuctionStatus | null),
    highestBid: rawHighestBid ? parseInt(rawHighestBid, 10) : 0,
    highestBidder: rawHighestBidder,
  };
}

/**
 * Açık artırmayı kapatır.
 * Status 'closed' yapıldıktan sonra Lua script yeni teklifleri reddeder.
 */
export async function closeAuction(adId: string): Promise<void> {
  await redis.set(keys.status(adId), "closed");
}
