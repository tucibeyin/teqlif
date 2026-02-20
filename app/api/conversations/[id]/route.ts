import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

export async function GET(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const { id } = await params;
        const currentUser = await getMobileUser(request);
        if (!currentUser) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const conversation = await prisma.conversation.findUnique({
            where: {
                id: id,
                OR: [
                    { user1Id: currentUser.id },
                    { user2Id: currentUser.id },
                ],
            },
            include: {
                user1: { select: { id: true, name: true, avatar: true } },
                user2: { select: { id: true, name: true, avatar: true } },
                ad: { select: { id: true, title: true, images: true } }
            }
        });

        if (!conversation) {
            return NextResponse.json({ message: 'Sohbet bulunamadı' }, { status: 404 });
        }

        return NextResponse.json(conversation);
    } catch (error) {
        console.error('Get Conversation Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
