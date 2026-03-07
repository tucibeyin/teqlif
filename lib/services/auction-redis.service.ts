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
  | { accepted: false; reason: "auction_not_active" | "bid_too_low" | "not_active_item" };

// ── Channel Types ─────────────────────────────────────────────────────────────

export type ChannelStatus = "live" | "offline";

export interface ChannelState {
  status: ChannelStatus | null;
  activeAdId: string | null;
}

// ── Key Helpers ───────────────────────────────────────────────────────────────

const keys = {
  status: (adId: string) => `auction:${adId}:status`,
  highestBid: (adId: string) => `auction:${adId}:highest_bid`,
  highestBidder: (adId: string) => `auction:${adId}:highest_bidder`,
} as const;

const channelKeys = {
  status: (hostId: string) => `channel:${hostId}:status`,
  activeAd: (hostId: string) => `channel:${hostId}:active_ad`,
} as const;

// ── Lua Script ────────────────────────────────────────────────────────────────

/**
 * Atomik teklif scripti. Race condition'ı Redis tek-thread garantisi ile engeller.
 *
 * KEYS[1] = auction:{adId}:status
 * KEYS[2] = auction:{adId}:highest_bid
 * KEYS[3] = auction:{adId}:highest_bidder
 * KEYS[4] = channel:{hostId}:active_ad   ← Opsiyonel. Kanal kontrolü için.
 *
 * ARGV[1] = bidAmount (integer string)
 * ARGV[2] = userId
 * ARGV[3] = adId  ← KEYS[4] varsa, active_ad ile karşılaştırılır.
 *
 * Dönüş değerleri:
 *   0 → açık artırma aktif değil
 *   1 → teklif reddedildi (mevcut fiyata eşit veya düşük)
 *   2 → teklif kabul edildi
 *   3 → bu ilan şu an kanalın aktif ürünü değil
 */
const PLACE_BID_SCRIPT = `
  local status = redis.call("GET", KEYS[1])
  if status ~= "active" then
    return 0
  end

  if #KEYS >= 4 then
    local activeAd = redis.call("GET", KEYS[4])
    if activeAd ~= ARGV[3] then
      return 3
    end
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
 *
 * channelHostId verilirse, adId'nin o kanalın aktif ürünü olup olmadığı da kontrol edilir.
 * Eski ürünlere gelen teklifler "not_active_item" hatası ile reddedilir.
 */
export async function placeBid(
  adId: string,
  userId: string,
  bidAmount: number,
  channelHostId?: string
): Promise<BidResult> {
  const evalKeys = [
    keys.status(adId),
    keys.highestBid(adId),
    keys.highestBidder(adId),
    ...(channelHostId ? [channelKeys.activeAd(channelHostId)] : []),
  ];

  const result = (await redis.eval(
    PLACE_BID_SCRIPT,
    evalKeys.length,
    ...evalKeys,
    bidAmount.toString(),
    userId,
    adId
  )) as number;

  if (result === 0) return { accepted: false, reason: "auction_not_active" };
  if (result === 1) return { accepted: false, reason: "bid_too_low" };
  if (result === 3) return { accepted: false, reason: "not_active_item" };

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
  const pipeline = redis.pipeline();
  pipeline.set(keys.status(adId), "closed");
  pipeline.del(keys.highestBid(adId));
  pipeline.del(keys.highestBidder(adId));
  await pipeline.exec();
}

// ── Channel Service ───────────────────────────────────────────────────────────

/**
 * Yayıncı kanalını başlatır. Status 'live' yapılır.
 * LiveKit odası açılırken çağrılmalıdır.
 */
export async function startChannel(hostId: string): Promise<void> {
  await redis.set(channelKeys.status(hostId), "live");
}

/**
 * Kanalı kapatır. Status 'offline' yapılır, aktif ürün temizlenir.
 * LiveKit odası kapatılırken çağrılmalıdır.
 */
export async function stopChannel(hostId: string): Promise<void> {
  const pipeline = redis.pipeline();
  pipeline.set(channelKeys.status(hostId), "offline");
  pipeline.del(channelKeys.activeAd(hostId));
  await pipeline.exec();
}

/**
 * Kanala yeni ürün sabitler.
 * 1. Varsa önceki ilanın açık artırmasını kapatır.
 * 2. Yeni ürünü `active_ad` olarak atar.
 * 3. Yeni ürün için açık artırmayı başlatır (state sıfırlanır).
 */
export async function pinItemToChannel(
  hostId: string,
  adId: string,
  startingBid: number = 0
): Promise<void> {
  // Önceki aktif ürün varsa ihalesini kapat.
  const prevAdId = await redis.get(channelKeys.activeAd(hostId));
  if (prevAdId && prevAdId !== adId) {
    const pipeline = redis.pipeline();
    pipeline.set(keys.status(prevAdId), "closed");
    pipeline.del(keys.highestBid(prevAdId));
    pipeline.del(keys.highestBidder(prevAdId));
    await pipeline.exec();
  }

  // Yeni ürünü aktifte başlat.
  const pipeline = redis.pipeline();
  pipeline.set(channelKeys.activeAd(hostId), adId);
  pipeline.set(keys.status(adId), "active");
  pipeline.set(keys.highestBid(adId), startingBid);
  pipeline.del(keys.highestBidder(adId));
  await pipeline.exec();
}

/**
 * Kanaldan aktif ürünü kaldırır. İhalenin kendisini kapatmaz —
 * sadece `active_ad` bağını siler. İhaleyi bitirmek için ayrıca closeAuction çağrılmalıdır.
 */
export async function unpinItem(hostId: string): Promise<void> {
  await redis.del(channelKeys.activeAd(hostId));
}

/**
 * Kanalın anlık durumunu döner (status + aktif ürün).
 */
export async function getChannelState(hostId: string): Promise<ChannelState> {
  const [rawStatus, rawActiveAd] = await redis.mget(
    channelKeys.status(hostId),
    channelKeys.activeAd(hostId)
  );

  return {
    status: (rawStatus as ChannelStatus | null),
    activeAdId: rawActiveAd,
  };
}
