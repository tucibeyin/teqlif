import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Oturum açmanız gerekiyor' }, { status: 401 });

        const conversations = await prisma.conversation.findMany({
            where: {
                OR: [
                    { user1Id: currentUser.id },
                    { user2Id: currentUser.id },
                ],
            },
            include: {
                user1: { select: { id: true, name: true, email: true, avatar: true } },
                user2: { select: { id: true, name: true, email: true, avatar: true } },
                ad: { select: { id: true, title: true, images: true } },
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1, // Get the latest message for preview
                },
                _count: {
                    select: {
                        messages: {
                            where: {
                                isRead: false,
                                senderId: { not: currentUser.id }
                            }
                        }
                    }
                }
            },
            orderBy: {
                updatedAt: 'desc',
            },
        });

        return NextResponse.json(conversations);
    } catch (error) {
        console.error('Fetch Conversations Error:', error);
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

        const { userId, adId } = await request.json();

        if (!userId) {
            return NextResponse.json({ message: 'Eksik veri: userId' }, { status: 400 });
        }

        if (currentUser.id === userId) {
            return NextResponse.json({ message: 'Kendinize mesaj gönderemezsiniz' }, { status: 400 });
        }

        // Try to find existing
        let conversation = await prisma.conversation.findFirst({
            where: {
                OR: [
                    { user1Id: currentUser.id, user2Id: userId, adId: adId || null },
                    { user1Id: userId, user2Id: currentUser.id, adId: adId || null }
                ]
            }
        });

        if (!conversation) {
            conversation = await prisma.conversation.create({
                data: {
                    user1Id: currentUser.id,
                    user2Id: userId,
                    adId: adId || null,
                }
            });
        }

        return NextResponse.json(conversation);
    } catch (error) {
        console.error('Create/Get Conversation Error:', error);
        return NextResponse.json(
            { message: 'Bir hata oluştu' },
            { status: 500 }
        );
    }
}
