import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

// GET all favorites for the current user
export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser?.id) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const favorites = await prisma.favorite.findMany({
            where: { userId: currentUser.id },
            include: {
                ad: {
                    include: {
                        category: true,
                        province: true,
                        bids: {
                            orderBy: { amount: 'desc' },
                            take: 1
                        },
                        _count: {
                            select: { bids: true }
                        }
                    }
                }
            },
            orderBy: { createdAt: 'desc' },
        });

        // Format similarly to normal ads to match mobile app expectations
        const formattedFavorites = favorites.map(fav => {
            const ad = fav.ad;
            return {
                ...ad,
                highestBidAmount: ad.bids[0]?.amount || null,
                count: {
                    bids: ad._count.bids
                }
            };
        });

        return NextResponse.json(formattedFavorites);
    } catch (error) {
        console.error('Fetch Favorites Error:', error);
        return NextResponse.json(
            { message: 'Favoriler getirilirken bir hata oluştu' },
            { status: 500 }
        );
    }
}

// POST: Add an ad to favorites
export async function POST(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser?.id) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const body = await request.json();
        const { adId } = body;

        if (!adId) {
            return NextResponse.json({ message: 'Missing adId' }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({
            where: { id: adId }
        });

        if (!ad || ad.status !== 'ACTIVE') {
            return NextResponse.json(
                { message: 'Bu ilan aktif olmadığı için favorilere eklenemez' },
                { status: 400 }
            );
        }

        const favorite = await prisma.favorite.create({
            data: {
                userId: currentUser.id,
                adId,
            }
        });

        return NextResponse.json(favorite);
    } catch (error: any) {
        if (error.code === 'P2002') {
            // Unique constraint failed, already favorited
            return NextResponse.json(
                { message: 'Bu ilan zaten favorilerinizde' },
                { status: 409 }
            );
        }
        console.error('Add Favorite Error:', error);
        return NextResponse.json(
            { message: 'Favoriye eklenirken bir hata oluştu' },
            { status: 500 }
        );
    }
}
