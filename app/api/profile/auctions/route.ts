import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });

        const [won, sold] = await Promise.all([
            // Auctions the current user WON (they were the buyer)
            prisma.ad.findMany({
                where: { status: 'SOLD', winnerId: currentUser.id },
                orderBy: { updatedAt: 'desc' },
                include: {
                    user: { select: { id: true, name: true, email: true, avatar: true } }, // seller
                    bids: {
                        where: { status: 'ACCEPTED' },
                        take: 1,
                        select: { amount: true },
                    },
                },
            }),
            // Auctions the current user SOLD (they were the seller)
            prisma.ad.findMany({
                where: { status: 'SOLD', userId: currentUser.id },
                orderBy: { updatedAt: 'desc' },
                include: {
                    bids: {
                        where: { status: 'ACCEPTED' },
                        take: 1,
                        include: {
                            user: { select: { id: true, name: true, email: true, avatar: true } }, // winner/buyer
                        },
                    },
                },
            }),
        ]);

        return NextResponse.json({ won, sold });
    } catch (error) {
        console.error('Auction History Error:', error);
        return NextResponse.json({ message: 'Bir hata oluştu' }, { status: 500 });
    }
}
