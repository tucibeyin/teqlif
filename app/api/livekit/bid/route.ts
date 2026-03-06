import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { placeBid } from "@/lib/services/auction-redis.service";
import { getMobileUser } from "@/lib/mobile-auth";


export async function POST(req: NextRequest) {
  try {
    // ── Auth (Supports both Web Session and Mobile JWT) ─────────────────────
    const user = await getMobileUser(req);

    if (!user?.id) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const userId = user.id;

    // ── Input Validation ────────────────────────────────────────────────────
    const body = await req.json();
    const { adId, amount } = body as { adId?: string; amount?: unknown };

    if (!adId || typeof adId !== "string") {
      return NextResponse.json({ error: "İlan ID'si zorunludur" }, { status: 400 });
    }
    if (typeof amount !== "number" || !Number.isInteger(amount) || amount <= 0) {
      return NextResponse.json(
        { error: "Teklif tutarı pozitif bir tam sayı olmalıdır" },
        { status: 400 }
      );
    }

    // ── Atomik Teklif (Lua Script via Redis) ────────────────────────────────
    const result = await placeBid(adId, userId, amount);

    if (!result.accepted) {
      const message =
        result.reason === "auction_not_active"
          ? "Açık arttırma henüz başlatılmadı"
          : "Teklifiniz en yüksek tekliften düşük";

      return NextResponse.json({ error: message }, { status: 400 });
    }

    // ── LiveKit DataChannel Broadcast ───────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (!apiKey || !apiSecret || !wsUrl) {
      console.error("[LiveKit Bid API] Missing environment variables");
      return NextResponse.json(
        { error: "Server configuration error" },
        { status: 500 }
      );
    }

    const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);

    const payload = JSON.stringify({
      type: "NEW_BID",
      amount: result.newHighestBid,
      bidderIdentity: userId,
    });

    await roomService.sendData(
      adId,
      new TextEncoder().encode(payload),
      1, // DataPacket_Kind.RELIABLE
      { topic: "auction_events" }
    );

    return NextResponse.json(
      { success: true, newHighestBid: result.newHighestBid },
      { status: 200 }
    );
  } catch (error) {
    console.error("[LiveKit Bid API] Unexpected error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
