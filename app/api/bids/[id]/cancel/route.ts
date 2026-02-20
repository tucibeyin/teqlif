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
        const bidId = resolvedParams.id;

        const bid = await prisma.bid.findUnique({
            where: { id: bidId },
            include: { ad: true, user: true }
        });

        if (!bid) {
            return NextResponse.json({ message: 'Teklif bulunamadı' }, { status: 404 });
        }

        if (bid.ad.userId !== session.user.id) {
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

            return result;
        });

        return NextResponse.json(updatedBid);
    } catch (error) {
        console.error("Cancel Bid Error:", error);
        return NextResponse.json({ message: 'Teklif iptal edilirken hata oluştu' }, { status: 500 });
    }
}
