import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';
import { sendPushNotification } from '@/lib/fcm';

export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Oturum açmanız gerekiyor' }, { status: 401 });

        const { searchParams } = new URL(request.url);
        const conversationId = searchParams.get('conversationId');

        if (!conversationId) {
            return NextResponse.json({ message: 'conversationId gerekli' }, { status: 400 });
        }

        // Validate if the user is part of the conversation
        const conversation = await prisma.conversation.findUnique({
            where: { id: conversationId },
        });

        if (!conversation || (conversation.user1Id !== currentUser.id && conversation.user2Id !== currentUser.id)) {
            return NextResponse.json({ message: 'Yetkisiz erişim' }, { status: 403 });
        }

        const read = searchParams.get('read') === 'true';
        const messages = await prisma.message.findMany({
            where: {
                conversationId,
            },
            include: {
                sender: {
                    select: { id: true, name: true, avatar: true },
                },
                parentMessage: {
                    include: {
                        sender: { select: { id: true, name: true } }
                    }
                }
            },
            orderBy: {
                createdAt: 'asc', // oldest to newest
            },
        });

        // Mark messages as read ONLY IF explicitly requested (e.g. window is focused)
        if (read) {
            await prisma.message.updateMany({
                where: {
                    conversationId,
                    senderId: { not: currentUser.id },
                    isRead: false
                },
                data: {
                    isRead: true
                }
            });
        }

        return NextResponse.json(messages);
    } catch (error) {
        console.error('Fetch Messages Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}

export async function POST(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });

        const { conversationId, content, recipientId, parentMessageId } = await request.json();

        if (!conversationId || !content || !recipientId) {
            return NextResponse.json({ message: 'Eksik veri' }, { status: 400 });
        }

        const recipient = await prisma.user.findUnique({
            where: { id: recipientId },
            select: { fcmToken: true }
        });

        const conversation = await prisma.conversation.findUnique({
            where: { id: conversationId },
            include: { ad: true }
        });

        if (!conversation) {
            return NextResponse.json({ message: 'Sohbet bulunamadı' }, { status: 404 });
        }

        if (conversation.adId === null) {
            return NextResponse.json({ message: 'Bu ilan yayından kaldırıldığı için yeni mesaj gönderilemez.' }, { status: 403 });
        }

        // Restriction: If sold, only winner or seller can talk
        if (conversation.ad?.status === 'SOLD') {
            const isWinner = conversation.ad.winnerId === currentUser.id;
            const isSeller = conversation.ad.userId === currentUser.id;

            if (!isWinner && !isSeller) {
                return NextResponse.json({
                    message: 'İlan satıldığı için bu sohbete devam edilemez.'
                }, { status: 403 });
            }
        }

        if (!conversation) {
            return NextResponse.json({ message: 'Sohbet bulunamadı' }, { status: 404 });
        }

        if (conversation.adId === null) {
            return NextResponse.json({ message: 'Bu ilan yayından kaldırıldığı için yeni mesaj gönderilemez.' }, { status: 403 });
        }

        const result = await prisma.$transaction(async (tx) => {
            const message = await tx.message.create({
                data: {
                    conversationId,
                    senderId: currentUser.id,
                    content,
                    parentMessageId: parentMessageId || null
                },
                include: {
                    sender: { select: { id: true, name: true, avatar: true } },
                    parentMessage: {
                        include: {
                            sender: { select: { id: true, name: true } }
                        }
                    }
                }
            });

            // Update conversation's updatedAt for sorting
            await tx.conversation.update({
                where: { id: conversationId },
                data: { updatedAt: new Date() }
            });

            // Create notification for recipient
            return message;
        });

        // Send push notification outside the transaction
        if (recipient?.fcmToken) {
            await sendPushNotification(
                recipient.fcmToken,
                'Yeni Mesaj 💬',
                `${currentUser.name}: ${content.substring(0, 50)}${content.length > 50 ? '...' : ''}`,
                { type: 'NEW_MESSAGE', link: `/dashboard/messages?conversationId=${conversationId}` }
            ).catch(err => console.error("FCM Send Error:", err));
        }

        return NextResponse.json(result);
    } catch (error) {
        console.error('Send Message Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
