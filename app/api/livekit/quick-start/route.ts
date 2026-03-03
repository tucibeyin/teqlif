import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { revalidatePath } from "next/cache";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
    try {
        const currentUser = await getMobileUser(req);
        if (!currentUser?.id) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        const body = await req.json();
        const { title, startingBid, images } = body;

        if (!title) {
            return NextResponse.json({ error: "Yayın başlığı zorunludur." }, { status: 400 });
        }

        // Fetch a default category to use for quick live ads
        const defaultCategory = await prisma.category.findFirst({
            where: { parentId: null }
        });

        if (!defaultCategory) {
            return NextResponse.json({ error: "Sistemde kategori bulunamadı, lütfen yöneticiyle iletişime geçin." }, { status: 500 });
        }

        // Fetch a default province and district
        const defaultProvince = await prisma.province.findFirst();
        if (!defaultProvince) {
            return NextResponse.json({ error: "Sistemde şehir bulunamadı." }, { status: 500 });
        }

        const defaultDistrict = await prisma.district.findFirst({
            where: { provinceId: defaultProvince.id }
        });

        if (!defaultDistrict) {
            return NextResponse.json({ error: "Sistemde ilçe bulunamadı." }, { status: 500 });
        }

        // Create the "Ghost Ad"
        const ghostAd = await prisma.ad.create({
            data: {
                title: title,
                description: "Hızlı Canlı Yayın (Ghost Ad)",
                price: Number(startingBid) || 1, // Store starting bid as price implicitly or default to 1
                isFixedPrice: false,
                startingBid: Number(startingBid) || 1,
                minBidStep: 1, // Default min step
                isLive: true,
                isAuction: true,
                status: "ACTIVE",
                userId: currentUser.id,
                categoryId: defaultCategory.id,
                provinceId: defaultProvince.id,
                districtId: defaultDistrict.id,
                images: images || [], // Supports passed images from mobile and web QuickLive
                expiresAt: new Date(Date.now() + 1 * 24 * 60 * 60 * 1000), // Expires in 1 day
            },
        });

        revalidatePath("/");

        return NextResponse.json({ id: ghostAd.id, message: "Hızlı yayın ilan oluşturuldu" }, { status: 201 });

    } catch (err) {
        console.error("POST /api/livekit/quick-start error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
