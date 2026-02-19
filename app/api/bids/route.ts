import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";

export async function POST(req: NextRequest) {
    try {
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        const { adId, amount } = await req.json();

        if (!adId || !amount) {
            return NextResponse.json({ error: "İlan ve teklif miktarı zorunludur." }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({
            where: { id: adId },
            include: {
                bids: { orderBy: { amount: "desc" }, take: 1 },
            },
        });

        if (!ad) {
            return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        }

        if (ad.userId === session.user.id) {
            return NextResponse.json({ error: "Kendi ilanınıza teklif veremezsiniz." }, { status: 403 });
        }

        if (ad.status !== "ACTIVE") {
            return NextResponse.json({ error: "Bu ilan artık aktif değil." }, { status: 400 });
        }

        const currentHighest = ad.bids[0]?.amount ?? ad.price;
        if (Number(amount) <= currentHighest) {
            return NextResponse.json(
                { error: `Teklifiniz mevcut en yüksek tekliften (${currentHighest} ₺) yüksek olmalıdır.` },
                { status: 400 }
            );
        }

        const bid = await prisma.bid.create({
            data: {
                amount: Number(amount),
                userId: session.user.id,
                adId,
            },
            include: { user: { select: { name: true } } },
        });

        return NextResponse.json(bid, { status: 201 });
    } catch (err) {
        console.error("POST /api/bids error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
