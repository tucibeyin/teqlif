import { NextResponse } from 'next/server';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';

export async function PATCH(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const session = await auth();

        if (!session?.user?.email) {
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
        const currentUser = await prisma.user.findUnique({
            where: { email: session.user.email },
        });

        if (!currentUser || currentUser.id !== bid.ad.userId) {
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

        return NextResponse.json(result);
    } catch (error) {
        console.error('Bid Accept Error:', error);
        return NextResponse.json(
            { message: 'Teklif kabul edilirken bir hata oluştu' },
            { status: 500 }
        );
    }
}
