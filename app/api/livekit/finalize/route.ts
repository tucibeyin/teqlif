import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { notifyAuctionWinner } from "@/lib/fcm";
import {
  closeAuction,
  getAuctionState,
} from "@/lib/services/auction-redis.service";
import { redis } from "@/lib/redis";
import { revalidatePath } from "next/cache";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/finalize
 *
 * Host "Kabul Et ve Sat" butonuna bastığında tetiklenir.
 *
 * Body: { adId: string, isQuickLive?: boolean }
 *
 * Akış:
 *  1. Auth + sahiplik kontrolü
 *  2. Redis'i kilitle (closeAuction) → artık teklif kabul edilmez
 *  3. Redis'ten nihai kazananı ve fiyatı çek (source of truth)
 *  4. Prisma transaction: Bid.create + Ad.update (+ isQuickLive için clone receipt)
 *  5. LiveKit DataChannel: AUCTION_ENDED sinyali
 *  6. Redis temizliği
 *  7. FCM bildirimi (fire-and-forget)
 */
export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const caller = await getMobileUser(req);
    if (!caller?.id) {
      return NextResponse.json(
        { error: "Giriş yapmanız gerekiyor." },
        { status: 401 }
      );
    }
    const callerId = caller.id;

    // ── Input Validation ──────────────────────────────────────────────────────
    const body = await req.json();
    const { adId, isQuickLive, channelHostId } = body as {
      adId?: string;
      isQuickLive?: boolean;
      channelHostId?: string;
    };

    if (!adId || typeof adId !== "string") {
      return NextResponse.json(
        { error: "adId zorunludur." },
        { status: 400 }
      );
    }

    // ── Prisma: İlan sahipliği kontrolü ───────────────────────────────────────
    const ad = await prisma.ad.findUnique({ where: { id: adId } });
    if (!ad) {
      return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
    }
    if (ad.userId !== callerId) {
      return NextResponse.json(
        { error: "Bu işlemi gerçekleştirme yetkiniz yok." },
        { status: 403 }
      );
    }

    // ── Redis: İhaleyi Kilitle ────────────────────────────────────────────────
    // Bu çağrıdan sonra Lua script yeni teklifleri reddeder.
    await closeAuction(adId);

    // ── Redis: Nihai Kazananı Çek ─────────────────────────────────────────────
    const { highestBid, highestBidder } = await getAuctionState(adId);

    // Hiç teklif gelmemişse ihale kazanansız kapanır.
    if (!highestBidder || highestBid <= 0) {
      revalidatePath(`/ad/${adId}`);
      revalidatePath("/");
      return NextResponse.json(
        { success: true, message: "İhale kazanansız kapandı.", winner: null },
        { status: 200 }
      );
    }

    // ── Prisma Transaction: Kalıcı Kayıt ─────────────────────────────────────
    let notifyAdId = adId;

    const { updatedAd, conversation } = await prisma.$transaction(async (tx) => {
      // 1. Kazanan teklifi veritabanına yaz
      await tx.bid.create({
        data: {
          amount: highestBid,
          userId: highestBidder,
          adId,
          status: "ACCEPTED",
        },
      });

      let txUpdatedAd;

      if (isQuickLive) {
        // QuickLive: Ana ilan aktif kalır (bir sonraki tur için),
        // bu satış için ayrı bir makbuz (receipt) klonu oluşturulur.
        txUpdatedAd = await tx.ad.update({
          where: { id: adId },
          data: {
            isAuctionActive: false,
            winnerId: highestBidder,
          },
        });

        const dynamicTitle =
          "Canlı Yayın Ürünü - " +
          new Date().toLocaleTimeString("tr-TR");

        const receipt = await tx.ad.create({
          data: {
            title: dynamicTitle,
            description: ad.description || "Hızlı Canlı Yayın Makbuzu",
            images: ad.images ?? [],
            price: highestBid,
            isFixedPrice: false,
            isAuction: true,
            isLive: false,
            status: "SOLD",
            userId: ad.userId,
            categoryId: ad.categoryId,
            provinceId: ad.provinceId,
            districtId: ad.districtId,
            winnerId: highestBidder,
          },
        });

        notifyAdId = receipt.id;

        // Bir sonraki tur için geçmiş teklifleri temizle
        await tx.bid.deleteMany({ where: { adId } });
      } else {
        // Standart ihalede ilan doğrudan SOLD yapılır.
        txUpdatedAd = await tx.ad.update({
          where: { id: adId },
          data: {
            status: "SOLD",
            isLive: false,
            isAuctionActive: false,
            winnerId: highestBidder,
            price: highestBid,
          },
        });
      }

      // 2. Kazanan ile mesajlaşma kanalı oluştur (yoksa)
      let txConversation = await tx.conversation.findUnique({
        where: {
          user1Id_user2Id_adId: {
            user1Id: callerId,
            user2Id: highestBidder,
            adId,
          },
        },
      });

      if (!txConversation) {
        txConversation = await tx.conversation.findUnique({
          where: {
            user1Id_user2Id_adId: {
              user1Id: highestBidder,
              user2Id: callerId,
              adId,
            },
          },
        });
      }

      if (!txConversation) {
        txConversation = await tx.conversation.create({
          data: { user1Id: callerId, user2Id: highestBidder, adId },
        });
      }

      // 3. Otomatik tebrik mesajı gönder
      await tx.message.create({
        data: {
          conversationId: txConversation.id,
          senderId: callerId,
          content: `Tebrikler! "${ad.title}" ilanının açık arttırmasını ${highestBid} ₺ bedelle kazandınız. Sizinle iletişime geçeceğim.`,
        },
      });

      return { updatedAd: txUpdatedAd, conversation: txConversation };
    });

    // ── LiveKit: AUCTION_ENDED Sinyali ────────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (apiKey && apiSecret && wsUrl) {
      // Kazananın gerçek ismini çek (id yerine isim göstermek için)
      const winnerUser = await prisma.user.findUnique({
        where: { id: highestBidder },
        select: { name: true },
      });

      const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
      const winnerName = winnerUser?.name || "Katılımcı";
      const targetRoom = channelHostId ? `channel:${channelHostId}` : adId;
      const payload = JSON.stringify({
        type: "AUCTION_ENDED",
        adId,
        adTitle: ad.title,
        sellerName: caller.name,
        winnerId: highestBidder,
        winner: winnerName,
        winnerName,
        amount: highestBid,
      });

      roomService
        .sendData(targetRoom, new TextEncoder().encode(payload), 1, {
          topic: "auction_events",
        })
        .catch((err) =>
          console.error("[AUCTION_ENDED] LiveKit broadcast error:", err)
        );
    } else {
      console.warn("[AUCTION_ENDED] LiveKit env variables missing — skipping broadcast");
    }

    // ── Redis Temizliği ───────────────────────────────────────────────────────
    // DB yazımı başarılı olduktan sonra geçici state temizlenir.
    await redis
      .del(
        `auction:${adId}:status`,
        `auction:${adId}:highest_bid`,
        `auction:${adId}:highest_bidder`
      )
      .catch((err) =>
        console.error("[FINALIZE] Redis cleanup error (non-critical):", err)
      );

    revalidatePath(`/ad/${adId}`);
    revalidatePath("/");

    // ── FCM: Kazanana Bildirim (fire-and-forget) ──────────────────────────────
    notifyAuctionWinner(highestBidder, notifyAdId, highestBid).catch((err) =>
      console.error("[FINALIZE] Winner notify error:", err)
    );

    return NextResponse.json(
      {
        success: true,
        message: "Satış başarıyla tamamlandı.",
        ad: updatedAd,
        winner: highestBidder,
        amount: highestBid,
      },
      { status: 200 }
    );
  } catch (err) {
    console.error("POST /api/livekit/finalize error:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
