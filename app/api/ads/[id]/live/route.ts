import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";
import { getMobileUser } from "@/lib/mobile-auth";
import { logger } from "@/lib/logger";
import { notifyFollowersOfLive } from "@/lib/fcm";
import { startAuction, closeAuction } from "@/lib/services/auction-redis.service";

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

        // 🔄 Session Start Protection: Force auction reset when stream starts
        if (isLive === true && !ad.isLive) {
            if (isAuctionActive !== true) {
                updateData.isAuctionActive = false;
                await closeAuction(id);
            }
        }

        // If restarting an auction, reset status and archive old bids
        if (isAuctionActive === true && ad.isAuctionActive === false) {
            updateData.status = 'ACTIVE';

            // Archive existing pending or accepted bids to start fresh
            await prisma.bid.updateMany({
                where: { adId: id },
                data: { isArchived: true, status: 'REJECTED' }
            });

            // 🔄 Synchronize Redis state (RESET live bid tracking)
            await startAuction(id, ad.startingBid ?? 0);
        }

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: updateData,
        });

        // 🔔 PHASE 20: Notify followers when live stream STARTS (false → true transition)
        if (isLive === true && !ad.isLive) {
            const hostUser = await prisma.user.findUnique({ where: { id: user.id }, select: { name: true } });
            const hostName = hostUser?.name ?? 'Bir satıcı';
            // Fire-and-forget — do NOT await to avoid delaying the response
            notifyFollowersOfLive(user.id, hostName, id).catch((err) =>
                logger.liveKit("ERROR", "LIVE_NOTIFY", `Follower notification failed for ad ${id}`, err)
            );
        }

        // ⛔ Müzayede/Yayın bittiğinde fiziksel silme (delete) KURALLARA AYKIRI! Sadece bayrakları indiriyoruz.
        if (isLive === false || isAuctionActive === false) {
            const isQuickLive = ad.description === 'Hızlı Canlı Yayın (Ghost Ad)';
            await prisma.ad.update({
                where: { id },
                data: {
                    isLive: isLive !== undefined ? Boolean(isLive) : ad.isLive,
                    isAuctionActive: false,
                    ...(isQuickLive && isLive === false ? { status: 'EXPIRED' } : {})
                }
            });
            // 🔄 Synchronize Redis state (STOP live bid tracking)
            await closeAuction(id);
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

