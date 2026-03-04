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

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı yönetme yetkiniz yok." }, { status: 403 });

        // Reject and archive all bids for this ad to start from 0
        await prisma.bid.updateMany({
            where: { adId: id },
            data: { isArchived: true, status: 'REJECTED' }
        });

        revalidatePath(`/ad/${id}`);
        revalidatePath("/");

        logger.info("Auction bids reset triggered by host", { adId: id, userId: user.id });
        return NextResponse.json({ message: "Açık arttırma teklifleri sıfırlandı." }, { status: 200 });
    } catch (err) {
        logger.error(`POST /api/ads/${await params.then(p => p.id)}/auction/reset error`, err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
