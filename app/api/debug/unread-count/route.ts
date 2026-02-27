import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getUnreadCount } from '@/lib/fcm';

export async function GET(request: Request) {
    const { searchParams } = new URL(request.url);
    const userId = searchParams.get('userId');

    if (!userId) return NextResponse.json({ error: 'userId required' }, { status: 400 });

    const msgCount = await prisma.message.count({
        where: {
            conversation: {
                OR: [
                    { user1Id: userId },
                    { user2Id: userId }
                ]
            },
            senderId: { not: userId },
            isRead: false
        }
    });

    const notifCount = await prisma.notification.count({
        where: {
            userId: userId,
            isRead: false
        }
    });

    const fcmCount = await getUnreadCount(userId);

    const sampleMessages = await prisma.message.findMany({
        where: {
            conversation: {
                OR: [
                    { user1Id: userId },
                    { user2Id: userId }
                ]
            },
            senderId: { not: userId },
            isRead: false
        },
        take: 5,
        select: { id: true, content: true, senderId: true, isRead: true }
    });

    const sampleNotifs = await prisma.notification.findMany({
        where: { userId, isRead: false },
        take: 5
    });

    return NextResponse.json({
        userId,
        msgCount,
        notifCount,
        fcmCount,
        sampleMessages,
        sampleNotifs
    });
}
