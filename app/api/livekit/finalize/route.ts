import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { notifyAuctionWinner } from "@/lib/fcm";
import { revalidatePath } from "next/cache";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/finalize
 *
 * Securely finalizes a live auction sale. Only the ad owner (Host) may call this.
 *
 * Body: { adId: string, winnerId: string, finalPrice: number }
 *
 * Actions:
 *  1. Validates host ownership
 *  2. Updates Ad: status=SOLD, isLive=false, isAuctionActive=false,
 *                 winnerId=winnerId, price=finalPrice
 *  3. Sends AUCTION_WON FCM push + in-app notification to winner
 */
export async function POST(req: NextRequest) {
    try {
        // getMobileUser handles both web (cookie session) and mobile (JWT Bearer)
        const caller = await getMobileUser(req);
        if (!caller?.id) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }
        const callerId = caller.id;

        const body = await req.json();
        const { adId, winnerId, finalPrice, isQuickLive } = body as {
            adId: string;
            winnerId: string;
            finalPrice: number;
            isQuickLive?: boolean;
        };

        if (!adId || !winnerId || finalPrice == null) {
            return NextResponse.json({ error: "adId, winnerId ve finalPrice zorunludur." }, { status: 400 });
        }

        // Security: only the Host (ad owner) may finalize
        const ad = await prisma.ad.findUnique({ where: { id: adId } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== callerId) {
            return NextResponse.json({ error: "Bu işlemi gerçekleştirme yetkiniz yok." }, { status: 403 });
        }

        let updatedAd;
        let notifyAdId = adId;

        if (isQuickLive) {
            // [Phase 24.4] Clone receipt logic
            updatedAd = await prisma.ad.update({
                where: { id: adId },
                data: {
                    isAuctionActive: false, // temporarily suspend auctioning for UI climax
                },
            });

            // Create clone receipt
            try {
                const receipt = await prisma.ad.create({
                    data: {
                        title: "Canlı Yayından Satın Alınan Ürün",
                        description: ad.description,
                        images: ad.images ?? [],
                        price: finalPrice,
                        isFixedPrice: false,
                        isAuction: true,
                        isLive: false,
                        status: "SOLD",
                        userId: ad.userId,
                        categoryId: ad.categoryId,
                        provinceId: ad.provinceId,
                        districtId: ad.districtId,
                        winnerId: winnerId,
                    }
                });
                notifyAdId = receipt.id;
            } catch (error) {
                console.error("Clone creation failed:", error);
            }

            // Clean up bids for the next round
            await prisma.bid.deleteMany({
                where: { adId: adId }
            });

        } else {
            // Standard finalized procedure
            updatedAd = await prisma.ad.update({
                where: { id: adId },
                data: {
                    status: "SOLD",
                    isLive: false,
                    isAuctionActive: false,
                    winnerId,
                    price: finalPrice,
                },
            });
        }

        revalidatePath(`/ad/${adId}`);
        revalidatePath("/");

        // Fire-and-forget winner notification (never delays response)
        notifyAuctionWinner(winnerId, notifyAdId, finalPrice).catch((err) =>
            console.error("[FINALIZE] Winner notify error:", err)
        );

        return NextResponse.json({
            success: true,
            message: "Satış başarıyla tamamlandı.",
            ad: updatedAd,
        }, { status: 200 });

    } catch (err) {
        console.error("POST /api/livekit/finalize error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
