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

/**
 * Kanala sabitlenmiş ürünün standart temsili.
 * isStaticAd: true  → mevcut bir ilan (Prisma'dan)
 * isStaticAd: false → anlık (on-the-fly) ürün
 */
export interface ActiveItem {
  id: string;
  title: string;
  price: number;
  imageUrl?: string;
  isStaticAd: boolean;
}

export interface ChannelState {
  status: ChannelStatus | null;
  activeItem: ActiveItem | null;
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
  title: (hostId: string) => `channel:${hostId}:title`,
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
  const evalKeys = [
    keys.status(adId),
    keys.highestBid(adId),
    keys.highestBidder(adId),
  ];

  const result = (await redis.eval(
    PLACE_BID_SCRIPT,
    evalKeys.length,
    ...evalKeys,
    bidAmount.toString(),
    userId
  )) as number;

  if (result === 0) return { accepted: false, reason: "auction_not_active" };
  if (result === 1) return { accepted: false, reason: "bid_too_low" };

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
 * Sadece status 'closed' yapılır; highest_bid ve highest_bidder key'leri
 * finalize sonrası ayrı bir temizlik adımında silinir (önce kazananı oku,
 * sonra temizle). Lua script status != "active" görünce yeni teklifleri reddeder.
 */
export async function closeAuction(adId: string): Promise<void> {
  await redis.set(keys.status(adId), "closed");
}

// ── Channel Service ───────────────────────────────────────────────────────────

/**
 * Yayıncı kanalını başlatır. Status 'live' yapılır.
 * LiveKit odası açılırken çağrılmalıdır.
 */
export async function startChannel(hostId: string, title?: string): Promise<void> {
  const pipeline = redis.pipeline();
  pipeline.set(channelKeys.status(hostId), "live");
  pipeline.del(channelKeys.activeAd(hostId));
  if (title) {
    pipeline.set(channelKeys.title(hostId), title);
  } else {
    pipeline.del(channelKeys.title(hostId));
  }
  await pipeline.exec();
}

/**
 * Kanala ait özel başlığı döner. Başlık yoksa null.
 */
export async function getChannelTitle(hostId: string): Promise<string | null> {
  return redis.get(channelKeys.title(hostId));
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
 * Kanala yeni ürün sabitler (ActiveItem JSON olarak saklanır).
 * 1. Varsa önceki ürünün açık artırmasını kapatır.
 * 2. Yeni ActiveItem'ı JSON olarak `active_ad` key'ine yazar.
 * 3. Yeni ürün için açık artırmayı başlatır (state sıfırlanır).
 */
export async function pinItemToChannel(
  hostId: string,
  activeItem: ActiveItem,
  startingBid: number = 0
): Promise<void> {
  // Önceki aktif ürün varsa ihalesini kapat.
  const prevJson = await redis.get(channelKeys.activeAd(hostId));
  if (prevJson) {
    try {
      const prev = JSON.parse(prevJson) as ActiveItem;
      if (prev.id !== activeItem.id) {
        const pipeline = redis.pipeline();
        pipeline.set(keys.status(prev.id), "closed");
        pipeline.del(keys.highestBid(prev.id));
        pipeline.del(keys.highestBidder(prev.id));
        await pipeline.exec();
      }
    } catch {
      // Bozuk/eski format — yoksay, devam et.
    }
  }

  // Yeni ürünü aktifte başlat.
  const pipeline = redis.pipeline();
  pipeline.set(channelKeys.activeAd(hostId), JSON.stringify(activeItem));
  pipeline.set(keys.status(activeItem.id), "active");
  pipeline.set(keys.highestBid(activeItem.id), startingBid);
  pipeline.del(keys.highestBidder(activeItem.id));
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
 * active_ad key'i JSON formatında ActiveItem içerir.
 */
export async function getChannelState(hostId: string): Promise<ChannelState> {
  const [rawStatus, rawActiveItem] = await redis.mget(
    channelKeys.status(hostId),
    channelKeys.activeAd(hostId)
  );

  let activeItem: ActiveItem | null = null;
  if (rawActiveItem) {
    try {
      activeItem = JSON.parse(rawActiveItem) as ActiveItem;
    } catch {
      // Bozuk/eski format — null döndür.
    }
  }

  return {
    status: (rawStatus as ChannelStatus | null),
    activeItem,
  };
}
