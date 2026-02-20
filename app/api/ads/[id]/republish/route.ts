import { NextResponse } from 'next/server';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';

export async function PATCH(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ message: 'Yetkisiz erişim' }, { status: 401 });
        }

        const resolvedParams = await params;
        const adId = resolvedParams.id;

        const ad = await prisma.ad.findUnique({
            where: { id: adId }
        });

        if (!ad) {
            return NextResponse.json({ message: 'İlan bulunamadı' }, { status: 404 });
        }

        if (ad.userId !== session.user.id) {
            return NextResponse.json({ message: 'Bu işlem için yetkiniz yok' }, { status: 403 });
        }

        const updatedAd = await prisma.ad.update({
            where: { id: adId },
            data: {
                status: 'ACTIVE',
                expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // Extend by 30 days
            }
        });

        return NextResponse.json(updatedAd);
    } catch (error) {
        console.error("Republish Error:", error);
        return NextResponse.json({ message: 'İlan yenilenirken bir hata oluştu' }, { status: 500 });
    }
}
