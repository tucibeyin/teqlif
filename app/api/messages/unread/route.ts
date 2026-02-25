import { NextResponse } from 'next/server';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

export async function GET(request: Request) {
    try {
        const session = await auth();
        const mobileUser = await getMobileUser(request);

        const userId = session?.user?.id || mobileUser?.id;

        if (!userId) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

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
