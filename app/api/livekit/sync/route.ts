import { NextRequest, NextResponse } from "next/server";
import { getMobileUser } from "@/lib/mobile-auth";
import { getAuctionState } from "@/lib/services/auction-redis.service";
import type { AuctionState } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

export interface SyncResponse {
  adId: string;
  status: AuctionState["status"];
  highestBid: number;
  highestBidder: string | null;
  isAuctionActive: boolean;
}

export async function GET(req: NextRequest) {
  const caller = await getMobileUser(req);
  if (!caller?.id) {
    return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
  }

  const adId = req.nextUrl.searchParams.get("adId");

  let auctionData = {};
  if (adId) {
    const state = await getAuctionState(adId);
    auctionData = {
      status: state.status,
      highestBid: state.highestBid,
      highestBidder: state.highestBidder,
      isAuctionActive: state.status === "active",
    };
  }

  const body = {
    ...auctionData,
    adId, // null ise null döner
    serverTime: Date.now(),
  };

  return NextResponse.json(body, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
