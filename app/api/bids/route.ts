import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { actionRatelimiter } from "@/lib/rate-limit";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(req: NextRequest) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const ip = req.headers.get("x-forwarded-for") ?? "anonymous";
        try {
            const { success } = await actionRatelimiter.limit(ip);
            if (!success) {
                return NextResponse.json({ error: "Çok hızlı teklif veriyorsunuz. Lütfen biraz yavaşlayın." }, { status: 429 });
            }
        } catch (ratelimitError) {
            console.error("Rate limit check failed (Bid):", ratelimitError);
            // Fail-open: allow the request to pass if Redis is unreachable
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

        if (ad.userId === user.id) {
            return NextResponse.json({ error: "Kendi ilanınıza teklif veremezsiniz." }, { status: 403 });
        }

        if (ad.status !== "ACTIVE") {
            return NextResponse.json({ error: "Bu ilan artık aktif değil." }, { status: 400 });
        }

        // Determine the minimum required bid
        let minRequiredAmount = 1; // absolute minimum for a free bid

        if (ad.bids.length > 0) {
            // If there are existing bids, the new bid must be at least (highest bid + minBidStep)
            minRequiredAmount = ad.bids[0].amount + ad.minBidStep;
        } else if (ad.startingBid !== null) {
            // If there are no bids but a starting bid is defined, the first bid can be exactly the starting bid
            minRequiredAmount = ad.startingBid;
        }

        if (Number(amount) < minRequiredAmount) {
            return NextResponse.json(
                { error: `Teklifiniz minimum ${new Intl.NumberFormat("tr-TR").format(minRequiredAmount)} ₺ olmalıdır.` },
                { status: 400 }
            );
        }

        const bid = await prisma.bid.create({
            data: {
                amount: Number(amount),
                userId: user.id,
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
