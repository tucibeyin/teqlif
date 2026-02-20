import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";
import { getMobileUser } from "@/lib/mobile-auth";

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const { id } = await params;
        const ad = await prisma.ad.findUnique({
            where: { id },
            include: {
                user: { select: { id: true, name: true, email: true, phone: true } },
                category: true,
                province: true,
                district: true,
                bids: {
                    include: { user: { select: { id: true, name: true } } },
                    orderBy: { amount: "desc" },
                },
            },
        });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        return NextResponse.json(ad);
    } catch (err) {
        console.error("GET /api/ads/[id] error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const { id } = await params;
        const body = await req.json();
        const { title, description, price } = body;

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Yetkiniz yok." }, { status: 403 });

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: {
                ...(title && { title }),
                ...(description && { description }),
                ...(price !== undefined && { price: Number(price) }),
            },
        });

        revalidatePath("/");
        revalidatePath("/dashboard");
        return NextResponse.json(updatedAd);
    } catch (err) {
        console.error("PATCH /api/ads/[id] error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}

export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const { id } = await params;
        const { title, description, price, startingBid, categorySlug, provinceId, districtId, images } = await req.json();

        if (!title || !description || !price || !categorySlug || !provinceId || !districtId) {
            return NextResponse.json({ error: "Tüm alanlar zorunludur." }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı düzenleme yetkiniz yok." }, { status: 403 });

        const category = await prisma.category.findUnique({ where: { slug: categorySlug } });
        if (!category) return NextResponse.json({ error: "Geçersiz kategori." }, { status: 400 });

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: {
                title, description,
                price: Number(price),
                startingBid: startingBid !== undefined ? Number(startingBid) : null,
                categoryId: category.id,
                provinceId, districtId,
                images: images || [],
            },
        });

        revalidatePath("/");
        revalidatePath("/dashboard");
        return NextResponse.json(updatedAd, { status: 200 });
    } catch (err) {
        console.error("PUT /api/ads/[id] error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const user = await getMobileUser(req);
        if (!user) return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });

        const { id } = await params;
        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı silme yetkiniz yok." }, { status: 403 });

        await prisma.ad.delete({ where: { id } });
        revalidatePath("/");
        revalidatePath("/dashboard");
        return NextResponse.json({ success: true }, { status: 200 });
    } catch (err) {
        console.error("DELETE /api/ads/[id] error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
