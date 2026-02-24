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

        // Privacy Logic
        const currentUser = await getMobileUser(_req);

        if (!currentUser) {
            (ad.user as any) = { id: ad.user.id, name: "Gizli Kullanıcı", email: "", phone: null };
            ad.bids.forEach((bid: any) => {
                bid.user.name = "Gizli Kullanıcı";
            });
        } else if (currentUser.id !== ad.userId) {
            const nameParts = ad.user.name.trim().split(" ");
            let maskedName = ad.user.name;
            if (nameParts.length > 1) {
                const firstName = nameParts.slice(0, -1).join(" ");
                const lastName = nameParts[nameParts.length - 1];
                maskedName = `${firstName} ${lastName.charAt(0)}.`;
            } else if (nameParts.length === 1 && nameParts[0].length > 1) {
                maskedName = `${nameParts[0].charAt(0)}.`;
            }
            ad.user.name = maskedName;

            if (!ad.showPhone) {
                ad.user.phone = null;
            }
        }

        // Mask bidders (everyone sees masked bidders except the bidder themselves)
        ad.bids.forEach((bid: any) => {
            if (currentUser?.id !== bid.user.id) {
                const parts = bid.user.name.trim().split(" ");
                if (parts.length > 1) {
                    const firstName = parts.slice(0, -1).join(" ");
                    const lastName = parts[parts.length - 1];
                    bid.user.name = `${firstName} ${lastName.charAt(0)}.`;
                } else if (parts.length === 1 && parts[0].length > 1) {
                    bid.user.name = `${parts[0].charAt(0)}.`;
                }
            }
        });

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
        const { title, description, price, startingBid, minBidStep, isFixedPrice, buyItNowPrice, showPhone, categorySlug, provinceId, districtId: rawDistrictId, images } = await req.json();

        if (!title || !description || !price || !categorySlug || !provinceId || !rawDistrictId) {
            return NextResponse.json({ error: "Tüm alanlar zorunludur." }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({ where: { id } });
        if (!ad) return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        if (ad.userId !== user.id) return NextResponse.json({ error: "Bu ilanı düzenleme yetkiniz yok." }, { status: 403 });

        const category = await prisma.category.findUnique({ where: { slug: categorySlug } });
        if (!category) return NextResponse.json({ error: "Geçersiz kategori." }, { status: 400 });

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

        const updatedAd = await prisma.ad.update({
            where: { id },
            data: {
                title, description,
                price: Number(price),
                isFixedPrice: isFixedPrice !== undefined ? Boolean(isFixedPrice) : undefined,
                startingBid: isFixedPrice ? null : (startingBid !== undefined ? Number(startingBid) : null),
                minBidStep: isFixedPrice ? 1 : (minBidStep !== undefined ? Number(minBidStep) : undefined),
                buyItNowPrice: isFixedPrice ? null : (buyItNowPrice !== undefined ? (buyItNowPrice ? Number(buyItNowPrice) : null) : undefined),
                showPhone: showPhone !== undefined ? Boolean(showPhone) : undefined,
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
