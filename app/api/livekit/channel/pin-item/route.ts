import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { getMobileUser } from "@/lib/mobile-auth";
import { prisma } from "@/lib/prisma";
import { pinItemToChannel } from "@/lib/services/auction-redis.service";
import type { ActiveItem } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/channel/pin-item
 *
 * İki mod desteklenir:
 *   A) Mevcut ilan: { adId: string, startingBid?: number }
 *   B) Anlık ürün:  { customTitle: string, customPrice?: number, startingBid?: number }
 *
 * Kanala yeni ürün sabitler:
 *   1. Mod A'da adId sahipliğini Prisma ile doğrular; mod B'de doğrulama gerekmez (host kendisi giriyor).
 *   2. ActiveItem oluşturur ve Redis'e JSON olarak yazar; önceki ihaleyi kapatır.
 *   3. channel:{hostId} LiveKit odasına ITEM_PINNED sinyalini ActiveItem ile birlikte fırlatır.
 *
 * Response: { success: true, activeItem, startingBid }
 */
export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const currentUser = await getMobileUser(req);
    if (!currentUser?.id) {
      return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
    }
    const hostId = currentUser.id;

    // ── Input Parsing ─────────────────────────────────────────────────────────
    const body = await req.json() as {
      adId?: string;
      customTitle?: string;
      customPrice?: unknown;
      startingBid?: unknown;
    };

    const { adId, customTitle } = body;

    const startingBidNum =
      typeof body.startingBid === "number" && Number.isFinite(body.startingBid) && body.startingBid >= 0
        ? Math.floor(body.startingBid)
        : 0;

    let activeItem: ActiveItem;

    if (adId && typeof adId === "string") {
      // ── Mod A: Mevcut ilan ──────────────────────────────────────────────────
      const ad = await prisma.ad.findUnique({
        where: { id: adId },
        select: { userId: true, title: true, price: true, startingBid: true, images: true },
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

      const adPrice = startingBidNum > 0
        ? startingBidNum
        : ((ad.price ?? ad.startingBid) ?? 0);

      activeItem = {
        id: adId,
        title: ad.title,
        price: adPrice,
        imageUrl: (ad.images as string[])[0] ?? undefined,
        isStaticAd: true,
      };

    } else if (customTitle && typeof customTitle === "string" && customTitle.trim()) {
      // ── Mod B: Anlık (on-the-fly) ürün ────────────────────────────────────
      const customPrice =
        typeof body.customPrice === "number" && Number.isFinite(body.customPrice) && body.customPrice >= 0
          ? Math.floor(body.customPrice)
          : startingBidNum;

      activeItem = {
        id: `custom_${Date.now()}`,
        title: customTitle.trim(),
        price: customPrice,
        isStaticAd: false,
      };

    } else {
      return NextResponse.json(
        { error: "adId veya customTitle zorunludur." },
        { status: 400 }
      );
    }

    // ── Redis: Önceki ihaleyi kapat, yeni ürünü başlat ───────────────────────
    await pinItemToChannel(hostId, activeItem, startingBidNum);

    // ── LiveKit: ITEM_PINNED Sinyali (ActiveItem JSON ile) ────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (!apiKey || !apiSecret || !wsUrl) {
      console.error("[channel/pin-item] LiveKit env değişkenleri eksik.");
      return NextResponse.json({ error: "Sunucu yapılandırma hatası." }, { status: 500 });
    }

    const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
    const roomName = `channel:${hostId}`;

    const payload = JSON.stringify({
      type: "ITEM_PINNED",
      activeItem,
      startingBid: startingBidNum,
    });

    // Fire-and-forget — oda yoksa (henüz kimse katılmamışsa) hata yutulur.
    roomService
      .sendData(roomName, new TextEncoder().encode(payload), 1, { topic: "auction_events" })
      .catch((err) => console.error("[channel/pin-item] LiveKit broadcast hatası:", err));

    return NextResponse.json({ success: true, activeItem, startingBid: startingBidNum }, { status: 200 });
  } catch (err) {
    console.error("[channel/pin-item] Hata:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
