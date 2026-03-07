// ─── Shared Arena Types ───────────────────────────────────────────────────────

/**
 * Kanala sabitlenmiş ürünün standart temsili (backend ActiveItem ile birebir).
 * isStaticAd: true → mevcut ilan | false → on-the-fly ürün
 */
export interface ActiveItem {
    id: string;
    title: string;
    price: number;
    imageUrl?: string;
    isStaticAd: boolean;
}

export interface ArenaMessage {
    id: string;
    text: string;
    sender: string;
    senderId?: string;
}

export interface Reaction {
    id: string;
    emoji: string;
    left: number;
}

export interface StageRequest {
    id: string;
    name: string;
}

export interface AuctionResult {
    winnerName: string;
    price: number;
}

export type AuctionStatus = "IDLE" | "ACTIVE";

export interface CustomArenaLayoutProps {
    adId: string;
    sellerId: string;
    isOwner: boolean;
    buyItNowPrice?: number | null;
    startingBid?: number | null;
    minBidStep?: number;
    initialHighestBid?: number;
    initialIsAuctionActive?: boolean;
    role: string;
    wantsToPublish: boolean;
    adOwnerName?: string;
    isQuickLive?: boolean;
}
