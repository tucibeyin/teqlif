import { NextResponse } from 'next/server';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';

export async function GET() {
    try {
        const session = await auth();

        if (!session?.user?.id) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const userId = session.user.id;

        const unreadCount = await prisma.message.count({
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

        return NextResponse.json({ unreadCount });
    } catch (error) {
        console.error("Error fetching unread messages count:", error);
        return NextResponse.json(
            { message: 'Sunucu hatası' },
            { status: 500 }
        );
    }
}
