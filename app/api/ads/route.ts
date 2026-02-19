import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";

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

        const { title, description, price, categorySlug, provinceId, districtId } = await req.json();

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
                userId: session.user.id,
                categoryId: category.id,
                provinceId,
                districtId,
            },
        });

        return NextResponse.json(ad, { status: 201 });
    } catch (err) {
        console.error("POST /api/ads error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
