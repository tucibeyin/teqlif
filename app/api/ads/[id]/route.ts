import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";

export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        const { id } = await params;
        const { title, description, price, startingBid, categorySlug, provinceId, districtId, images } = await req.json();

        if (!title || !description || !price || !categorySlug || !provinceId || !districtId) {
            return NextResponse.json({ error: "Tüm alanlar zorunludur." }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({ where: { id } });

        if (!ad) {
            return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        }

        if (ad.userId !== session.user.id) {
            return NextResponse.json({ error: "Bu ilanı düzenleme yetkiniz yok." }, { status: 403 });
        }

        const category = await prisma.category.findUnique({ where: { slug: categorySlug } });
        if (!category) {
            return NextResponse.json({ error: "Geçersiz kategori." }, { status: 400 });
        }

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: {
                title,
                description,
                price: Number(price),
                startingBid: startingBid !== undefined ? Number(startingBid) : null,
                categoryId: category.id,
                provinceId,
                districtId,
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
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        const { id } = await params;
        const ad = await prisma.ad.findUnique({ where: { id } });

        if (!ad) {
            return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        }

        if (ad.userId !== session.user.id) {
            return NextResponse.json({ error: "Bu ilanı silme yetkiniz yok." }, { status: 403 });
        }

        await prisma.ad.delete({ where: { id } });

        revalidatePath("/");
        revalidatePath("/dashboard");

        return NextResponse.json({ success: true }, { status: 200 });
    } catch (err) {
        console.error("DELETE /api/ads/[id] error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
