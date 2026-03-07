import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { notifyAuctionWinner } from "@/lib/fcm";
import {
  closeAuction,
  getAuctionState,
  getChannelState,
} from "@/lib/services/auction-redis.service";
import { redis } from "@/lib/redis";
import { revalidatePath } from "next/cache";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/finalize
 *
 * Host "Kabul Et ve Sat" butonuna bastığında tetiklenir.
 *
 * Body: { adId: string, isQuickLive?: boolean, channelHostId?: string }
 *
 * Mod Ayrımı:
 *  - KANAL MODU  (isQuickLive=true veya adId="channel:{hostId}"):
 *      DB'de adId ile ilan aramaz. Redis'ten pinned adId'yi bulur,
 *      ihaleyi kilitler, kazananı okur ve Makbuz (Receipt) ilanı yarat.
 *  - KLASİK MOD  (isQuickLive=false, normal adId):
 *      DB'deki mevcut ilanı SOLD yapar, mesajlaşma başlatır.
 *
 * Her iki modda da AUCTION_ENDED topic'siz DataChannel ile yayınlanır.
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

    // ── Input ─────────────────────────────────────────────────────────────────
    const body = await req.json();
    const { adId, isQuickLive, channelHostId } = body as {
      adId?: string;
      isQuickLive?: boolean;
      channelHostId?: string;
    };

    if (!adId || typeof adId !== "string") {
      return NextResponse.json({ error: "adId zorunludur." }, { status: 400 });
    }

    // Kanal host ID'sini çöz: explicit param > adId prefix > null
    const effectiveHostId =
      channelHostId ??
      (adId.startsWith("channel:") ? adId.replace("channel:", "") : null);

    const isChannelMode = !!(isQuickLive || effectiveHostId);

    // =========================================================================
    // KANAL MODU
    // =========================================================================
    if (isChannelMode) {
      const hostId = effectiveHostId ?? callerId;

      // Sahiplik: çağıran kişi kanalın sahibi olmalı
      if (callerId !== hostId) {
        return NextResponse.json(
          { error: "Bu işlemi gerçekleştirme yetkiniz yok." },
          { status: 403 }
        );
      }

      // Redis: kanala sabitlenmiş aktif ürün ID'si
      const channelState = await getChannelState(hostId);
      const pinnedAdId = channelState.activeItem?.id;

      if (!pinnedAdId) {
        return NextResponse.json(
          { success: true, message: "Kanalda aktif ürün yok.", winner: null },
          { status: 200 }
        );
      }

      // 1. İhaleyi kilitle (Lua script artık yeni teklif kabul etmez)
      await closeAuction(pinnedAdId);

      // 2. Nihai kazananı oku (closeAuction artık bu key'leri silmiyor)
      const { highestBid, highestBidder } = await getAuctionState(pinnedAdId);

      if (!highestBidder || highestBid <= 0) {
        // Temizlik ve çık
        await redis
          .del(
            `auction:${pinnedAdId}:status`,
            `auction:${pinnedAdId}:highest_bid`,
            `auction:${pinnedAdId}:highest_bidder`
          )
          .catch(() => { });
        return NextResponse.json(
          { success: true, message: "İhale kazanansız kapandı.", winner: null },
          { status: 200 }
        );
      }

      // Pinned ilanın DB kaydını çek (başlık / kategori / görseller için)
      const pinnedAd = await prisma.ad.findUnique({ where: { id: pinnedAdId } });

      // Makbuz için zorunlu alanlar pinnedAd'den geliyor; bulunamazsa işlem yapılamaz
      if (!pinnedAd) {
        await redis
          .del(
            `auction:${pinnedAdId}:status`,
            `auction:${pinnedAdId}:highest_bid`,
            `auction:${pinnedAdId}:highest_bidder`
          )
          .catch(() => { });
        return NextResponse.json(
          { error: "Sabitlenen ürün DB'de bulunamadı." },
          { status: 404 }
        );
      }

      const receiptTitle = `${pinnedAd.title} - Canlı Yayın Satışı`;

      // 3. Prisma transaction: Makbuz ilanı + konuşma + mesaj
      let notifyAdId = pinnedAdId;

      const { receipt } = await prisma.$transaction(async (tx) => {
        // Kazanan teklifi kaydet
        await tx.bid.create({
          data: {
            amount: highestBid,
            userId: highestBidder,
            adId: pinnedAdId,
            status: "ACCEPTED",
          },
        });

        // Makbuz ilanı yarat (durum direkt SOLD, yayına çıkmaz)
        const newReceipt = await tx.ad.create({
          data: {
            title: receiptTitle,
            description: pinnedAd.description || "Canlı Yayın Kanalı Satışı",
            images: pinnedAd.images ?? [],
            price: highestBid,
            isFixedPrice: false,
            isAuction: true,
            isLive: false,
            status: "SOLD",
            userId: hostId,
            categoryId: pinnedAd.categoryId,
            provinceId: pinnedAd.provinceId,
            districtId: pinnedAd.districtId,
            winnerId: highestBidder,
          },
        });

        notifyAdId = newReceipt.id;

        // Satıcı ↔ alıcı konuşması (makbuz ilanı adına)
        let txConversation = await tx.conversation.findUnique({
          where: {
            user1Id_user2Id_adId: {
              user1Id: callerId,
              user2Id: highestBidder,
              adId: newReceipt.id,
            },
          },
        });
        if (!txConversation) {
          txConversation = await tx.conversation.findUnique({
            where: {
              user1Id_user2Id_adId: {
                user1Id: highestBidder,
                user2Id: callerId,
                adId: newReceipt.id,
              },
            },
          });
        }
        if (!txConversation) {
          txConversation = await tx.conversation.create({
            data: { user1Id: callerId, user2Id: highestBidder, adId: newReceipt.id },
          });
        }

        await tx.message.create({
          data: {
            conversationId: txConversation.id,
            senderId: callerId,
            content: `Tebrikler! "${receiptTitle}" açık arttırmasını ${highestBid} ₺ bedelle kazandınız. Sizinle iletişime geçeceğim.`,
          },
        });

        return { receipt: newReceipt };
      });

      // 4. LiveKit: AUCTION_ENDED → channel:{hostId} odasına (topic yok)
      const apiKey = process.env.LIVEKIT_API_KEY;
      const apiSecret = process.env.LIVEKIT_API_SECRET;
      const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

      if (apiKey && apiSecret && wsUrl) {
        const winnerUser = await prisma.user.findUnique({
          where: { id: highestBidder },
          select: { name: true },
        });
        const winnerName = winnerUser?.name || "Katılımcı";
        const payload = JSON.stringify({
          type: "AUCTION_ENDED",
          adId: pinnedAdId,
          adTitle: receiptTitle,
          sellerName: caller.name,
          winnerId: highestBidder,
          winner: winnerName,
          winnerName,
          amount: highestBid,
        });

        new RoomServiceClient(wsUrl, apiKey, apiSecret)
          .sendData(`channel:${hostId}`, new TextEncoder().encode(payload), 1)
          .catch((err) =>
            console.error("[AUCTION_ENDED] LiveKit broadcast error:", err)
          );
      } else {
        console.warn("[AUCTION_ENDED] LiveKit env variables missing — skipping broadcast");
      }

      // 5. Redis temizliği (DB yazımı başarılı olduktan sonra)
      await redis
        .del(
          `auction:${pinnedAdId}:status`,
          `auction:${pinnedAdId}:highest_bid`,
          `auction:${pinnedAdId}:highest_bidder`
        )
        .catch((err) =>
          console.error("[FINALIZE] Redis cleanup error (non-critical):", err)
        );

      // 6. FCM bildirimi (fire-and-forget)
      notifyAuctionWinner(highestBidder, notifyAdId, highestBid).catch((err) =>
        console.error("[FINALIZE] Winner notify error:", err)
      );

      return NextResponse.json(
        {
          success: true,
          message: "Satış başarıyla tamamlandı.",
          receipt,
          winner: highestBidder,
          amount: highestBid,
        },
        { status: 200 }
      );
    }

    // =========================================================================
    // KLASİK İLAN MODU
    // =========================================================================

    // Sahiplik: DB'den ilanı bul ve sahibini kontrol et
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

    // 1. İhaleyi kilitle
    await closeAuction(adId);

    // 2. Nihai kazananı oku
    const { highestBid, highestBidder } = await getAuctionState(adId);

    if (!highestBidder || highestBid <= 0) {
      await redis
        .del(
          `auction:${adId}:status`,
          `auction:${adId}:highest_bid`,
          `auction:${adId}:highest_bidder`
        )
        .catch(() => { });
      revalidatePath(`/ad/${adId}`);
      revalidatePath("/");
      return NextResponse.json(
        { success: true, message: "İhale kazanansız kapandı.", winner: null },
        { status: 200 }
      );
    }

    // 3. Prisma transaction: Teklif + İlan güncelle + Konuşma + Mesaj
    const { updatedAd } = await prisma.$transaction(async (tx) => {
      await tx.bid.create({
        data: {
          amount: highestBid,
          userId: highestBidder,
          adId,
          status: "ACCEPTED",
        },
      });

      const txUpdatedAd = await tx.ad.update({
        where: { id: adId },
        data: {
          status: "SOLD",
          isLive: false,
          isAuctionActive: false,
          winnerId: highestBidder,
          price: highestBid,
        },
      });

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

      await tx.message.create({
        data: {
          conversationId: txConversation.id,
          senderId: callerId,
          content: `Tebrikler! "${ad.title}" ilanının açık arttırmasını ${highestBid} ₺ bedelle kazandınız. Sizinle iletişime geçeceğim.`,
        },
      });

      return { updatedAd: txUpdatedAd, conversation: txConversation };
    });

    // 4. LiveKit: AUCTION_ENDED → ilan odası (topic yok)
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (apiKey && apiSecret && wsUrl) {
      const winnerUser = await prisma.user.findUnique({
        where: { id: highestBidder },
        select: { name: true },
      });
      const winnerName = winnerUser?.name || "Katılımcı";
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

      new RoomServiceClient(wsUrl, apiKey, apiSecret)
        .sendData(adId, new TextEncoder().encode(payload), 1)
        .catch((err) =>
          console.error("[AUCTION_ENDED] LiveKit broadcast error:", err)
        );
    } else {
      console.warn("[AUCTION_ENDED] LiveKit env variables missing — skipping broadcast");
    }

    // 5. Redis temizliği
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

    // 6. FCM bildirimi (fire-and-forget)
    notifyAuctionWinner(highestBidder, adId, highestBid).catch((err) =>
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
