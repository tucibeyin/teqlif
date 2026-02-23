import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Oturum açmanız gerekiyor' }, { status: 401 });

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
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });

        const body = await request.json().catch(() => ({}));
        const { id } = body;

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

export async function DELETE(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });

        const url = new URL(request.url);
        const id = url.searchParams.get("id");

        if (id) {
            await prisma.notification.delete({
                where: { id, userId: currentUser.id }
            });
        } else {
            await prisma.notification.deleteMany({
                where: { userId: currentUser.id }
            });
        }

        return NextResponse.json({ success: true, message: 'Bildirim(ler) silindi' });
    } catch (error) {
        console.error('Delete Notifications Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
