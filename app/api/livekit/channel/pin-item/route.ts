import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { getMobileUser } from "@/lib/mobile-auth";
import { prisma } from "@/lib/prisma";
import { pinItemToChannel } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/channel/pin-item
 * Body: { adId: string, startingBid?: number }
 *
 * Kanala yeni ürün sabitler:
 *   1. adId'nin gerçek sahibinin isteği atan kişi olduğunu Prisma ile doğrular.
 *   2. Önceki ihaleyi kapatır, yeni ürünü active_ad olarak atar, yeni ihaleyi başlatır.
 *   3. channel:{hostId} LiveKit odasına ITEM_PINNED DataChannel sinyali fırlatır.
 *
 * Response: { success: true, adId, startingBid }
 */
export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const currentUser = await getMobileUser(req);
    if (!currentUser?.id) {
      return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
    }
    const hostId = currentUser.id;

    // ── Input Validation ──────────────────────────────────────────────────────
    const body = await req.json();
    const { adId, startingBid } = body as { adId?: string; startingBid?: unknown };

    if (!adId || typeof adId !== "string") {
      return NextResponse.json({ error: "adId zorunludur." }, { status: 400 });
    }

    const startingBidNum =
      typeof startingBid === "number" && Number.isFinite(startingBid) && startingBid >= 0
        ? Math.floor(startingBid)
        : 0;

    // ── Sahiplik Doğrulaması (Prisma) ─────────────────────────────────────────
    const ad = await prisma.ad.findUnique({
      where: { id: adId },
      select: { userId: true },
    });

    if (!ad) {
      return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
    }

    if (ad.userId !== hostId) {
      return NextResponse.json(
        { error: "Bu ilanı kanalınıza sabitlemek için yetkiniz yok." },
        { status: 403 }
      );
    }

    // ── Redis: Önceki ihaleyi kapat, yeni ürünü başlat ───────────────────────
    await pinItemToChannel(hostId, adId, startingBidNum);

    // ── LiveKit: ITEM_PINNED Sinyali ──────────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (!apiKey || !apiSecret || !wsUrl) {
      console.error("[channel/pin-item] LiveKit env değişkenleri eksik.");
      return NextResponse.json({ error: "Sunucu yapılandırma hatası." }, { status: 500 });
    }

    const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
    const roomName = `channel:${hostId}`;

    const payload = JSON.stringify({ type: "ITEM_PINNED", adId, startingBid: startingBidNum });

    // Fire-and-forget — oda yoksa (henüz kimse katılmamışsa) hata yutulur.
    roomService
      .sendData(roomName, new TextEncoder().encode(payload), 1, { topic: "auction_events" })
      .catch((err) => console.error("[channel/pin-item] LiveKit broadcast hatası:", err));

    return NextResponse.json({ success: true, adId, startingBid: startingBidNum }, { status: 200 });
  } catch (err) {
    console.error("[channel/pin-item] Hata:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
