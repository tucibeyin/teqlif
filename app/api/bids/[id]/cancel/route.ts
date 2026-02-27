import { NextResponse } from 'next/server';
import { getMobileUser } from '@/lib/mobile-auth';
import { prisma } from '@/lib/prisma';
import { revalidatePath } from 'next/cache';

export async function PATCH(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) {
            return NextResponse.json({ message: 'Yetkisiz erişim' }, { status: 401 });
        }

        const resolvedParams = await params;
        const bidId = resolvedParams.id;

        const bid = await prisma.bid.findUnique({
            where: { id: bidId },
            include: { ad: true, user: true }
        });

        if (!bid) {
            return NextResponse.json({ message: 'Teklif bulunamadı' }, { status: 404 });
        }

        if (bid.ad.userId !== currentUser.id) {
            return NextResponse.json({ message: 'Bu işlem için yetkiniz yok' }, { status: 403 });
        }

        if (bid.status !== 'ACCEPTED' && bid.status !== 'PENDING') {
            return NextResponse.json({ message: 'Geçersiz teklif durumu' }, { status: 400 });
        }

        // İptal işlemleri
        const updatedBid = await prisma.$transaction(async (tx) => {
            const result = await tx.bid.update({
                where: { id: bidId },
                data: { status: 'REJECTED' }
            });

            const text = bid.status === 'ACCEPTED'
                ? `"${bid.ad.title}" ilanına verdiğiniz teklifin kabul işlemi satıcı tarafından iptal edildi. İlan hala aktif, yeni teklif verebilirsiniz.`
                : `"${bid.ad.title}" ilanına verdiğiniz teklif satıcı tarafından reddedildi. İlan hala aktif, yeni teklif verebilirsiniz.`;

            // Bildirim gönder
            await tx.notification.create({
                data: {
                    userId: bid.userId,
                    type: 'SYSTEM',
                    message: text,
                    link: `/ad/${bid.adId}`,
                }
            });

            // If the ad is currently SOLD, check if we should reactivate it
            const currentAd = await tx.ad.findUnique({
                where: { id: bid.adId },
                select: { status: true }
            });

            if (currentAd?.status === 'SOLD') {
                const acceptedBidsCount = await tx.bid.count({
                    where: {
                        adId: bid.adId,
                        status: 'ACCEPTED',
                        id: { not: bidId } // Exclude the one we just rejected
                    }
                });

                if (acceptedBidsCount === 0) {
                    await tx.ad.update({
                        where: { id: bid.adId },
                        data: { status: 'ACTIVE' }
                    });
                }
            }

            return result;
        });

        // Revalidate cache for the ad and the home page
        revalidatePath('/');
        revalidatePath(`/ad/${bid.adId}`);

        return NextResponse.json(updatedBid);
    } catch (error) {
        console.error("Cancel Bid Error:", error);
        return NextResponse.json({ message: 'Teklif iptal edilirken hata oluştu' }, { status: 500 });
    }
}
