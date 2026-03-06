import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { revalidatePath } from "next/cache";
import { closeAuction } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
    try {
        const caller = await getMobileUser(req);
        if (!caller?.id) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }
        const callerId = caller.id;

        const body = await req.json();
        const { adId } = body;

        if (!adId) {
            return NextResponse.json({ error: "adId zorunludur." }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({ where: { id: adId } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== callerId) {
            return NextResponse.json({ error: "Bu işlemi gerçekleştirme yetkiniz yok." }, { status: 403 });
        }

        const resetAd = await prisma.ad.update({
            where: { id: adId },
            data: {
                isAuctionActive: false,
                price: ad.startingPrice || ad.startingBid || 0, // Reset to starting bid or 0
                winnerId: null, // Critical: Clear the previous winner entirely!
            },
        });

        // Ensure bids are empty (in case finalize failed or didn't run properly)
        await prisma.bid.deleteMany({
            where: { adId: adId }
        });

        // 🔄 Synchronize Redis state (STOP live bid tracking and clear)
        await closeAuction(adId);

        revalidatePath(`/ad/${adId}`);

        return NextResponse.json({
            success: true,
            message: "Yeni müzayede başlatıldı.",
            ad: resetAd,
        }, { status: 200 });

    } catch (err) {
        console.error("POST /api/livekit/reset error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
