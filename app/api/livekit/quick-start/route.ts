import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { notifyFollowersOfLive } from "@/lib/fcm";
import { startChannel, pinItemToChannel } from "@/lib/services/auction-redis.service";
import { revalidatePath } from "next/cache";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const currentUser = await getMobileUser(req);
    if (!currentUser?.id) {
      return NextResponse.json(
        { error: "Giriş yapmanız gerekiyor." },
        { status: 401 }
      );
    }

    // ── Input Validation ──────────────────────────────────────────────────────
    const body = await req.json();
    const { title, startingBid, images } = body as {
      title?: string;
      startingBid?: number | string;
      images?: string[];
    };

    if (!title) {
      return NextResponse.json(
        { error: "Yayın başlığı zorunludur." },
        { status: 400 }
      );
    }

    // ── Prisma: Varsayılan kategori / şehir / ilçe ────────────────────────────
    const [defaultCategory, defaultProvince] = await Promise.all([
      prisma.category.findFirst({ where: { parentId: null } }),
      prisma.province.findFirst(),
    ]);

    if (!defaultCategory) {
      return NextResponse.json(
        { error: "Sistemde kategori bulunamadı, lütfen yöneticiyle iletişime geçin." },
        { status: 500 }
      );
    }
    if (!defaultProvince) {
      return NextResponse.json(
        { error: "Sistemde şehir bulunamadı." },
        { status: 500 }
      );
    }

    const defaultDistrict = await prisma.district.findFirst({
      where: { provinceId: defaultProvince.id },
    });
    if (!defaultDistrict) {
      return NextResponse.json(
        { error: "Sistemde ilçe bulunamadı." },
        { status: 500 }
      );
    }

    // ── Prisma: Ghost Ad Oluştur ───────────────────────────────────────────────
    const startingBidNum = Number(startingBid) || 1;

    const ghostAd = await prisma.ad.create({
      data: {
        title,
        description: "Hızlı Canlı Yayın (Ghost Ad)",
        price: startingBidNum,
        isFixedPrice: false,
        startingBid: startingBidNum,
        minBidStep: 1,
        isLive: true,
        isAuction: true,
        isAuctionActive: true,
        status: "ACTIVE",
        userId: currentUser.id,
        categoryId: defaultCategory.id,
        provinceId: defaultProvince.id,
        districtId: defaultDistrict.id,
        images: images ?? [],
        expiresAt: new Date(Date.now() + 1 * 24 * 60 * 60 * 1000),
      },
    });

    // ── Redis: Kanalı Başlat + Ghost Ad'ı Aktif Ürün Olarak Sabitle ──────────
    // startChannel → channel:{userId}:status = "live"
    // pinItemToChannel → channel:{userId}:active_ad = ghostAd.id + auction başlatır
    // Bu sayede viewer'lar kanal sync'te activeAdId'yi görür ve channelHostId ile teklif verebilir.
    await startChannel(currentUser.id);
    await pinItemToChannel(currentUser.id, ghostAd.id, startingBidNum);

    // ── LiveKit: AUCTION_START Sinyali ────────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    const channelRoom = `channel:${currentUser.id}`;

    if (apiKey && apiSecret && wsUrl) {
      const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
      // ITEM_PINNED: hem host hem viewer controller'ları activeAdId'yi günceller.
      const payload = JSON.stringify({ type: "ITEM_PINNED", adId: ghostAd.id, startingBid: startingBidNum });

      // Fire-and-forget: oda henüz yoksa hata yutulur; istemci token alınca zaten state'i çeker.
      roomService
        .sendData(channelRoom, new TextEncoder().encode(payload), 1, {
          topic: "auction_events",
        })
        .catch((err) =>
          console.error("[AUCTION_START] LiveKit broadcast error:", err)
        );
    } else {
      console.warn("[AUCTION_START] LiveKit env variables missing — skipping broadcast");
    }

    revalidatePath("/");

    // ── FCM: Takipçileri Bildir (fire-and-forget) ─────────────────────────────
    const hostName = currentUser.name ?? "Bir satıcı";
    notifyFollowersOfLive(currentUser.id, hostName, ghostAd.id).catch((err) =>
      console.error("[LIVE_NOTIFY] quick-start follower notify error:", err)
    );

    // roomName: istemci bu odaya bağlanmalı (channel:{userId})
    return NextResponse.json({ ...ghostAd, roomName: channelRoom }, { status: 201 });
  } catch (err) {
    console.error("POST /api/livekit/quick-start error:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
