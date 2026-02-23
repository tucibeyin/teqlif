import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

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

        const messages = await prisma.message.findMany({
            where: {
                conversationId,
            },
            include: {
                sender: {
                    select: { id: true, name: true, avatar: true },
                },
            },
            orderBy: {
                createdAt: 'asc', // oldest to newest
            },
        });

        // Mark messages as read automatically
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

        const { conversationId, content, recipientId } = await request.json();

        if (!conversationId || !content || !recipientId) {
            return NextResponse.json({ message: 'Eksik veri' }, { status: 400 });
        }

        const conversation = await prisma.conversation.findUnique({
            where: { id: conversationId }
        });

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
                    content
                },
                include: {
                    sender: { select: { id: true, name: true, avatar: true } }
                }
            });

            // Update conversation's updatedAt for sorting
            await tx.conversation.update({
                where: { id: conversationId },
                data: { updatedAt: new Date() }
            });

            // Create notification for recipient
            await tx.notification.create({
                data: {
                    userId: recipientId,
                    type: 'NEW_MESSAGE',
                    message: `${currentUser.name} sana yeni bir mesaj gönderdi.`,
                    link: `/dashboard/messages?conversationId=${conversationId}`
                }
            });

            return message;
        });

        return NextResponse.json(result);
    } catch (error) {
        console.error('Send Message Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
