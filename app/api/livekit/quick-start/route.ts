import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { notifyFollowersOfLive } from "@/lib/fcm";
import { startAuction } from "@/lib/services/auction-redis.service";
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

    // ── Redis: Açık Artırmayı Başlat ──────────────────────────────────────────
    // Ghost Ad ID'si hem Redis key hem LiveKit oda adı olarak kullanılır.
    await startAuction(ghostAd.id, startingBidNum);

    // ── LiveKit: AUCTION_START Sinyali ────────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (apiKey && apiSecret && wsUrl) {
      const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
      const payload = JSON.stringify({ type: "AUCTION_START" });

      // Fire-and-forget: oda henüz yoksa hata yutulur; istemci token alınca zaten state'i çeker.
      roomService
        .sendData(ghostAd.id, new TextEncoder().encode(payload), 1, {
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

    return NextResponse.json(ghostAd, { status: 201 });
  } catch (err) {
    console.error("POST /api/livekit/quick-start error:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
