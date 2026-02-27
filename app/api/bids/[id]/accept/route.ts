import { NextResponse } from 'next/server';
import { getMobileUser } from '@/lib/mobile-auth';
import { prisma } from '@/lib/prisma';
import { sendPushNotification } from '@/lib/fcm';
import { revalidatePath } from 'next/cache';

export async function PATCH(
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
                { message: 'Teklif bulunamadı' },
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

        // Update the bid status in a transaction, also creating the conversation and notification
        const result = await prisma.$transaction(async (tx) => {
            // 1. Accept the bid
            const acceptedBid = await tx.bid.update({
                where: { id: bidId },
                data: { status: 'ACCEPTED' },
            });

            // 2. Reject other pending bids for this ad (Optional but common practice)
            await tx.bid.updateMany({
                where: {
                    adId: bid.adId,
                    id: { not: bidId },
                    status: 'PENDING',
                },
                data: { status: 'REJECTED' },
            });

            // 2.5 Automatically toggle Ad Status to SOLD
            await tx.ad.update({
                where: { id: bid.adId },
                data: { status: 'SOLD' },
            });

            // 3. Create a notification for the bidder
            await tx.notification.create({
                data: {
                    userId: bid.userId,
                    type: 'BID_ACCEPTED',
                    message: `${bid.ad.title} ilanınız için verdiğiniz ${bid.amount} TL teklif kabul edildi! Satıcı ile iletişime geçebilirsiniz.`,
                    link: `/ad/${bid.adId}`,
                },
            });

            // 4. Create or get existing conversation between the ad owner and the bidder
            // Since they might have a conversation already, we upsert or just findFirst and create.
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
                // also check reverse order
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

            return { acceptedBid, conversation };
        });

        // Send push notification outside the transaction
        if (bid.user.fcmToken) {
            await sendPushNotification(
                bid.user.fcmToken,
                'Teklifin Kabul Edildi! 🎉',
                `${bid.ad.title} ilanı için verdiğin ${bid.amount} ₺ teklif kabul edildi! Satıcı ile hemen iletişime geçebilirsin.`,
                { type: 'BID_ACCEPTED', link: `/ad/${bid.adId}` }
            ).catch(err => console.error("FCM Send Error:", err));
        }

        // Revalidate cache for the ad and the home page
        revalidatePath('/');
        revalidatePath(`/ad/${bid.adId}`);

        return NextResponse.json(result);
    } catch (error) {
        console.error('Bid Accept Error:', error);
        return NextResponse.json(
            { message: 'Teklif kabul edilirken bir hata oluştu' },
            { status: 500 }
        );
    }
}
