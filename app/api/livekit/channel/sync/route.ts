import { NextRequest, NextResponse } from "next/server";
import { getMobileUser } from "@/lib/mobile-auth";
import {
  getChannelState,
  getAuctionState,
} from "@/lib/services/auction-redis.service";
import type { ChannelState, ActiveItem } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

export type AuctionSyncStatus = "IDLE" | "ACTIVE" | "SOLD";

/**
 * Unified sync response — hem Channel hem Ad oda tipi için aynı format.
 */
export interface ChannelSyncResponse {
  hostId: string;
  status: ChannelState["status"];
  activeItem: ActiveItem | null;
  auctionStatus: AuctionSyncStatus;
  highestBid: number;
  highestBidder: string | null;
}

function mapAuctionStatus(s: string | null): AuctionSyncStatus {
  if (s === "active") return "ACTIVE";
  if (s === "closed") return "SOLD";
  return "IDLE";
}

/**
 * GET /api/livekit/channel/sync?hostId=xxx
 *
 * Kanalın anlık durumunu döner. Late-joiner'lar bu endpoint ile senkronize olur.
 * Her iki oda tipi (Channel / Ad) için aynı unified format kullanılır.
 *
 * Cache-Control: no-store — her zaman taze veri.
 */
export async function GET(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const caller = await getMobileUser(req);
    if (!caller?.id) {
      return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
    }

    // ── Input Validation ──────────────────────────────────────────────────────
    const hostId = req.nextUrl.searchParams.get("hostId");
    if (!hostId) {
      return NextResponse.json({ error: "hostId zorunludur." }, { status: 400 });
    }

    // ── Redis: Kanal State ────────────────────────────────────────────────────
    const channelState = await getChannelState(hostId);

    // ── Redis: Aktif ürün varsa açık artırma state'i de çek ──────────────────
    let auctionStatus: AuctionSyncStatus = "IDLE";
    let highestBid = 0;
    let highestBidder: string | null = null;

    if (channelState.activeItem) {
      const auctionState = await getAuctionState(channelState.activeItem.id);
      auctionStatus = mapAuctionStatus(auctionState.status);
      highestBid = auctionState.highestBid;
      highestBidder = auctionState.highestBidder;
    }

    const body: ChannelSyncResponse = {
      hostId,
      status: channelState.status,
      activeItem: channelState.activeItem,
      auctionStatus,
      highestBid,
      highestBidder,
    };

    return NextResponse.json(body, {
      status: 200,
      headers: { "Cache-Control": "no-store" },
    });
  } catch (err) {
    console.error("[channel/sync] Hata:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
