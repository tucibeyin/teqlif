import { NextRequest, NextResponse } from "next/server";
import { getMobileUser } from "@/lib/mobile-auth";
import {
  getChannelState,
  getAuctionState,
} from "@/lib/services/auction-redis.service";
import type { ChannelState, AuctionState } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

export interface ChannelSyncResponse {
  hostId: string;
  channelStatus: ChannelState["status"];
  activeAdId: string | null;
  auction: {
    status: AuctionState["status"];
    highestBid: number;
    highestBidder: string | null;
    isAuctionActive: boolean;
  } | null;
}

/**
 * GET /api/livekit/channel/sync?hostId=xxx
 *
 * Kanalın anlık durumunu döner. Late-joiner'lar bu endpoint ile senkronize olur.
 *   - channel:{hostId}:status + channel:{hostId}:active_ad okunur.
 *   - Eğer activeAdId varsa, o ürünün açık artırma durumu da eklenir.
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
    let auctionData: ChannelSyncResponse["auction"] = null;
    if (channelState.activeAdId) {
      const auctionState = await getAuctionState(channelState.activeAdId);
      auctionData = {
        status: auctionState.status,
        highestBid: auctionState.highestBid,
        highestBidder: auctionState.highestBidder,
        isAuctionActive: auctionState.status === "active",
      };
    }

    const body: ChannelSyncResponse = {
      hostId,
      channelStatus: channelState.status,
      activeAdId: channelState.activeAdId,
      auction: auctionData,
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
