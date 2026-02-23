import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { actionRatelimiter } from "@/lib/rate-limit";
import { revalidatePath } from "next/cache";
import { getMobileUser } from "@/lib/mobile-auth";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
    try {
        const { searchParams } = new URL(req.url);
        const category = searchParams.get("category");
        const province = searchParams.get("province");
        const q = searchParams.get("q");
        const isMine = searchParams.get("mine") === "true";

        const where: Record<string, unknown> = { status: "ACTIVE" };
        if (category) where.category = { slug: category };
        if (province) where.provinceId = province;
        if (q) where.title = { contains: q, mode: "insensitive" };

        if (isMine) {
            const user = await getMobileUser(req);
            if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
            where.userId = user.id;
            delete where.status; // Allow users to see their own inactive/expired ads
        }

        const ads = await prisma.ad.findMany({
            where,
            take: 50,
            orderBy: { createdAt: "desc" },
            include: {
                user: { select: { name: true } },
                category: true,
                province: true,
                district: true,
                _count: { select: { bids: true } },
                bids: { orderBy: { amount: "desc" }, take: 1, select: { amount: true } },
            },
        });

        return NextResponse.json(ads);
    } catch (err) {
        console.error("GET /api/ads error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}

export async function POST(req: NextRequest) {
    try {
        const currentUser = await getMobileUser(req);
        if (!currentUser?.id) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        const ip = req.headers.get("x-forwarded-for") ?? "anonymous";
        try {
            const { success } = await actionRatelimiter.limit(ip);
            if (!success) {
                return NextResponse.json({ error: "Çok fazla istek gönderdiniz. Lütfen bir süre bekleyin." }, { status: 429 });
            }
        } catch (ratelimitError) {
            console.error("Rate limit check failed (Ad):", ratelimitError);
            // Fail-open: allow the request to pass if Redis is unreachable
        }

        const { title, description, price, startingBid, minBidStep, isFixedPrice, buyItNowPrice, showPhone, categorySlug, provinceId, districtId: rawDistrictId, images } = await req.json();

        if (!title || !description || !price || !categorySlug || !provinceId || !rawDistrictId) {
            return NextResponse.json({ error: "Tüm alanlar zorunludur." }, { status: 400 });
        }

        const category = await prisma.category.findUnique({ where: { slug: categorySlug } });
        if (!category) {
            return NextResponse.json({ error: "Geçersiz kategori." }, { status: 400 });
        }

        let districtId = rawDistrictId;
        const districtExists = await prisma.district.findUnique({ where: { id: districtId } });
        if (!districtExists) {
            const firstDistrict = await prisma.district.findFirst({ where: { provinceId } });
            if (firstDistrict) {
                districtId = firstDistrict.id;
            } else {
                return NextResponse.json({ error: "Geçersiz ilçe." }, { status: 400 });
            }
        }

        const ad = await prisma.ad.create({
            data: {
                title,
                description,
                price: Number(price),
                isFixedPrice: Boolean(isFixedPrice),
                startingBid: isFixedPrice ? null : (startingBid !== undefined ? Number(startingBid) : null),
                minBidStep: isFixedPrice ? 1 : (minBidStep !== undefined ? Number(minBidStep) : 1),
                buyItNowPrice: isFixedPrice ? null : (buyItNowPrice ? Number(buyItNowPrice) : null),
                showPhone: showPhone !== undefined ? Boolean(showPhone) : false,
                userId: currentUser.id,
                categoryId: category.id,
                provinceId,
                districtId,
                images: images || [],
                expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
            },
        });

        revalidatePath("/");
        revalidatePath("/dashboard");

        return NextResponse.json(ad, { status: 201 });
    } catch (err) {
        console.error("POST /api/ads error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
