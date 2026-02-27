import { NextResponse } from 'next/server';
import { getMobileUser } from '@/lib/mobile-auth';
import { prisma } from '@/lib/prisma';
import { revalidatePath } from 'next/cache';
import { logger } from '@/lib/logger';

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
        logger.info("PATCH /api/bids/[id]/cancel start", { bidId, userId: currentUser.id });

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
        const result = await prisma.$transaction(async (tx) => {
            const currentBid = await tx.bid.findUnique({
                where: { id: bidId },
                include: { ad: { select: { title: true, userId: true, id: true, status: true } } }
            });

            if (!currentBid) throw new Error('Teklif bulunamadı');
            if (currentBid.ad.userId !== currentUser.id) throw new Error('Yetkisiz işlem');

            const updatedBid = await tx.bid.update({
                where: { id: bidId },
                data: { status: 'REJECTED' }
            });

            const text = currentBid.status === 'ACCEPTED'
                ? `"${currentBid.ad.title}" ilanına verdiğiniz teklifin kabul işlemi satıcı tarafından iptal edildi. İlan hala aktif, yeni teklif verebilirsiniz.`
                : `"${currentBid.ad.title}" ilanına verdiğiniz teklif satıcı tarafından reddedildi. İlan hala aktif, yeni teklif verebilirsiniz.`;

            // Bildirim gönder
            await tx.notification.create({
                data: {
                    userId: currentBid.userId,
                    type: 'SYSTEM',
                    message: text,
                    link: `/ad/${currentBid.adId}`,
                }
            });

            // Status recovery check
            logger.info("Status recovery check (Inside TS)", { adId: currentBid.adId, adStatus: currentBid.ad.status });

            if (currentBid.ad.status === 'SOLD') {
                const acceptedBidsCount = await tx.bid.count({
                    where: {
                        adId: currentBid.adId,
                        status: 'ACCEPTED',
                        id: { not: bidId } // Exclude current
                    }
                });

                logger.info("Accepted bids remaining", { adId: currentBid.adId, count: acceptedBidsCount });

                if (acceptedBidsCount === 0) {
                    logger.info("Reactivating ad", { adId: currentBid.adId });
                    await tx.ad.update({
                        where: { id: currentBid.adId },
                        data: { status: 'ACTIVE' }
                    });
                }
            }

            return updatedBid;
        });

        // Revalidate cache for the ad and the home page
        revalidatePath('/');
        revalidatePath(`/ad/${bid.adId}`);

        return NextResponse.json(result);
    } catch (error) {
        console.error("Cancel Bid Error:", error);
        return NextResponse.json({ message: 'Teklif iptal edilirken hata oluştu' }, { status: 500 });
    }
}
