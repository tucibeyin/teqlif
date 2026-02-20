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

        // Determine the opening bid
        // If there's an explicit startingBid, use it as baseline
        // If startingBid is null, it means it's a "Free Bid" (Serbest Teklif), so the baseline is 0 (first bid can be anything >= 1)
        const baseline = ad.startingBid !== null ? ad.startingBid : 0;

        // The highest bid is either the first bid in db, or the baseline
        const currentHighest = ad.bids[0]?.amount ?? baseline;

        if (Number(amount) <= currentHighest) {
            return NextResponse.json(
                { error: `Teklifiniz minimum ${currentHighest + (ad.bids.length > 0 ? ad.minBidStep : 0)} ₺ olmalıdır.` },
                { status: 400 }
            );
        }

        // Explicit Free Bidding fallback rule (can't bid less than 1 ₺)
        if (Number(amount) < 1) {
            return NextResponse.json({ error: "Teklifiniz en az 1 ₺ olmalıdır." }, { status: 400 });
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
