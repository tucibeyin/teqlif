import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";
import { getMobileUser } from "@/lib/mobile-auth";

export const dynamic = 'force-dynamic';

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const { id } = await params;
        const body = await req.json();
        const { isLive, liveKitRoomId } = body;

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı yönetme yetkiniz yok." }, { status: 403 });

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: {
                isLive: isLive !== undefined ? Boolean(isLive) : ad.isLive,
                liveKitRoomId: liveKitRoomId !== undefined ? String(liveKitRoomId) : ad.liveKitRoomId,
            },
        });

        revalidatePath(`/ad/${id}`);
        revalidatePath("/");

        return NextResponse.json(updatedAd, { status: 200 });
    } catch (err) {
        console.error("POST /api/ads/[id]/live error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
