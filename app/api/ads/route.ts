import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import { actionRatelimiter } from "@/lib/rate-limit";
import { revalidatePath } from "next/cache";

export async function GET(req: NextRequest) {
    try {
        const { searchParams } = new URL(req.url);
        const category = searchParams.get("category");
        const province = searchParams.get("province");
        const q = searchParams.get("q");

        const where: Record<string, unknown> = { status: "ACTIVE" };
        if (category) where.category = { slug: category };
        if (province) where.provinceId = province;
        if (q) where.title = { contains: q, mode: "insensitive" };

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
        const session = await auth();
        if (!session?.user) {
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

        const { title, description, price, startingBid, categorySlug, provinceId, districtId, images } = await req.json();

        if (!title || !description || !price || !categorySlug || !provinceId || !districtId) {
            return NextResponse.json({ error: "Tüm alanlar zorunludur." }, { status: 400 });
        }

        const category = await prisma.category.findUnique({ where: { slug: categorySlug } });
        if (!category) {
            return NextResponse.json({ error: "Geçersiz kategori." }, { status: 400 });
        }

        const ad = await prisma.ad.create({
            data: {
                title,
                description,
                price: Number(price),
                startingBid: startingBid !== undefined ? Number(startingBid) : null,
                userId: session.user.id,
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
