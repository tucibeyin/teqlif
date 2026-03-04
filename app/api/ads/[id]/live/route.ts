import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";
import { getMobileUser } from "@/lib/mobile-auth";
import { logger } from "@/lib/logger";

export const dynamic = 'force-dynamic';

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const { id } = await params;
        const body = await req.json();
        const { isLive, liveKitRoomId, isAuctionActive } = body;

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı yönetme yetkiniz yok." }, { status: 403 });

        let updateData: any = {
            isLive: isLive !== undefined ? Boolean(isLive) : ad.isLive,
            liveKitRoomId: liveKitRoomId !== undefined ? String(liveKitRoomId) : ad.liveKitRoomId,
            isAuctionActive: isAuctionActive !== undefined ? Boolean(isAuctionActive) : ad.isAuctionActive,
        };

        // Reset auction status entirely when live stream ends
        if (updateData.isLive === false) {
            updateData.isAuctionActive = false;
        }

        // If restarting an auction, reset status and archive old bids
        if (isAuctionActive === true && ad.isAuctionActive === false) {
            updateData.status = 'ACTIVE';

            // Archive existing pending or accepted bids to start fresh
            await prisma.bid.updateMany({
                where: { adId: id },
                data: { isArchived: true, status: 'REJECTED' }
            });
        }

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: updateData,
            select: { id: true, isLive: true, startingBid: true }
        });

        // 4. Value Handoff (Static -> Live Engine)
        if (isLive === true) {
            // Find the highest static bid in Prisma
            const highestStaticBid = await prisma.bid.findFirst({
                where: { adId: id, status: { not: "REJECTED" } },
                orderBy: { amount: 'desc' },
                select: { amount: true }
            });

            // If a static bid exists, use it. Otherwise, use the Ad's startingBid or 0.
            const startingLivePrice = highestStaticBid?.amount || updatedAd.startingBid || 0;

            // Seed Redis Engine
            const { redis } = await import('@/lib/redis');
            await redis.set(`highest_bid:${id}`, startingLivePrice);
            console.log(`[Value Handoff] Initialized Redis for Ad ${id} with starting price: ${startingLivePrice}`);
        }

        // Ghost Ad Cleanup: If stream is ending and it is a ghost ad
        if (isLive === false && ad.description === 'Hızlı Canlı Yayın (Ghost Ad)') {
            logger.info("Ghost ad cleanup triggered", { adId: id });

            // Detach conversations before deleting to avoid foreign key constraints
            await prisma.conversation.updateMany({
                where: { adId: id },
                data: { adId: null }
            });

            await prisma.ad.delete({ where: { id } });
            revalidatePath("/");
            return NextResponse.json({ message: "Ghost ad cleaned up." }, { status: 200 });
        }

        revalidatePath(`/ad/${id}`);
        revalidatePath("/");

        logger.liveKit("INFO", "API_LIVE", `Ad ${id} live status updated to ${isLive}`, { userId: user.id });
        return NextResponse.json(updatedAd, { status: 200 });
    } catch (err) {
        logger.liveKit("ERROR", "API_LIVE", `POST /api/ads/${await params.then(p => p.id)}/live error`, err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
