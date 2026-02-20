import { NextResponse } from 'next/server';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';

export async function GET(request: Request) {
    try {
        const session = await auth();

        if (!session?.user?.email) {
            return NextResponse.json(
                { message: 'Oturum açmanız gerekiyor' },
                { status: 401 }
            );
        }

        const currentUser = await prisma.user.findUnique({
            where: { email: session.user.email },
        });

        if (!currentUser) return NextResponse.json({ message: 'User not found' }, { status: 404 });

        const notifications = await prisma.notification.findMany({
            where: {
                userId: currentUser.id,
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 20, // Limit to recent 20 for the dropdown
        });

        const unreadCount = await prisma.notification.count({
            where: {
                userId: currentUser.id,
                isRead: false
            }
        });

        return NextResponse.json({ notifications, unreadCount });
    } catch (error) {
        console.error('Fetch Notifications Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}

export async function PATCH(request: Request) {
    try {
        const session = await auth();
        if (!session?.user?.email) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const { id } = await request.json(); // if id is provided mark specific, else mark all

        const currentUser = await prisma.user.findUnique({
            where: { email: session.user.email },
        });

        if (!currentUser) return NextResponse.json({ message: 'User not found' }, { status: 404 });

        if (id) {
            await prisma.notification.updateMany({
                where: { id, userId: currentUser.id },
                data: { isRead: true }
            });
        } else {
            await prisma.notification.updateMany({
                where: { userId: currentUser.id, isRead: false },
                data: { isRead: true }
            });
        }

        return NextResponse.json({ success: true });
    } catch (error) {
        console.error('Update Notifications Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
