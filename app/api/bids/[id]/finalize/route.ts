import { NextResponse } from 'next/server';
import { getMobileUser } from '@/lib/mobile-auth';
import { prisma } from '@/lib/prisma';
import { sendPushNotification, getUnreadCount } from '@/lib/fcm';
import { revalidatePath } from 'next/cache';
import { logger } from '@/lib/logger';

export async function POST(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const currentUser = await getMobileUser(request);

        if (!currentUser) {
            return NextResponse.json(
                { message: 'Oturum açmanız gerekiyor' },
                { status: 401 }
            );
        }

        const resolvedParams = await params;
        const bidId = resolvedParams.id;
        logger.info("POST /api/bids/[id]/finalize start", { bidId, userId: currentUser.id });

        // Get the bid and the associated ad
        const bid = await prisma.bid.findUnique({
            where: { id: bidId },
            include: {
                ad: true,
                user: true,
            },
        });

        if (!bid) {
            return NextResponse.json(
                { message: 'Teqlif bulunamadı' },
                { status: 404 }
            );
        }

        // Verify the ad belongs to the logged in user
        if (currentUser.id !== bid.ad.userId) {
            return NextResponse.json(
                { message: 'Bu işlem için yetkiniz yok' },
                { status: 403 }
            );
        }

        if (bid.ad.status === 'SOLD') {
            return NextResponse.json(
                { message: 'Bu ilan zaten satıldı' },
                { status: 400 }
            );
        }

        if (bid.status !== 'ACCEPTED') {
            return NextResponse.json(
                { message: 'Sadece kabul edilmiş teqlifler için satış tamamlanabilir' },
                { status: 400 }
            );
        }

        // Finalize the sale
        const result = await prisma.$transaction(async (tx) => {
            // 1. Mark ad as SOLD and stop auction
            const updatedAd = await tx.ad.update({
                where: { id: bid.adId },
                data: {
                    status: 'SOLD',
                    winnerId: bid.userId,
                    isAuctionActive: false,
                },
            });

            // 2. Find or Create conversation
            let conversation = await tx.conversation.findUnique({
                where: {
                    user1Id_user2Id_adId: {
                        user1Id: currentUser.id,
                        user2Id: bid.userId,
                        adId: bid.adId,
                    }
                }
            });

            if (!conversation) {
                conversation = await tx.conversation.findUnique({
                    where: {
                        user1Id_user2Id_adId: {
                            user1Id: bid.userId,
                            user2Id: currentUser.id,
                            adId: bid.adId,
                        }
                    }
                });
            }

            if (!conversation) {
                conversation = await tx.conversation.create({
                    data: {
                        user1Id: currentUser.id,
                        user2Id: bid.userId,
                        adId: bid.adId,
                    }
                });
            }

            // 3. Create Automated "Congratulations" Message
            await tx.message.create({
                data: {
                    conversationId: conversation.id,
                    senderId: currentUser.id,
                    content: `Tebrikler! "${bid.ad.title}" ilanının açık arttırmasını ${bid.amount} ₺ bedelle kazandınız. Sizinle iletişime geçeceğim.`,
                }
            });

            // 4. Create a notification for the buyer
            await tx.notification.create({
                data: {
                    userId: bid.userId,
                    type: 'SYSTEM',
                    message: `${bid.ad.title} ilanındaki satış, satıcı tarafından onaylanıp tamamlandı. Hayırlı olsun! Mesaj kutunuzu kontrol edin.`,
                    link: `/ad/${bid.adId}`,
                },
            });

            return { updatedAd };
        });

        // Send push notification outside the transaction
        if (bid.user.fcmToken) {
            const badgeCount = await getUnreadCount(bid.userId);
            await sendPushNotification(
                bid.user.fcmToken,
                'Satış Tamamlandı! 🤝',
                `${bid.ad.title} ilanı için satış süreci tamamlandı. Hayırlı olsun!`,
                { type: 'SYSTEM', link: `/ad/${bid.adId}` },
                badgeCount
            ).catch(err => console.error("FCM Send Error:", err));
        }

        // Revalidate cache
        revalidatePath('/');
        revalidatePath(`/ad/${bid.adId}`);
        revalidatePath('/dashboard');

        return NextResponse.json(result);
    } catch (error) {
        console.error('Bid Finalize Error:', error);
        return NextResponse.json(
            { message: 'Satış tamamlanırken bir hata oluştu' },
            { status: 500 }
        );
    }
}
