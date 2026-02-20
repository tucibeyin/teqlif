import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';

export async function GET(request: Request) {
    try {
        const { searchParams } = new URL(request.url);
        const query = searchParams.get('q');

        if (!query || query.length < 2) {
            return NextResponse.json([]);
        }

        const ads = await prisma.ad.findMany({
            where: {
                status: 'ACTIVE',
                OR: [
                    { title: { contains: query, mode: 'insensitive' } },
                    { id: { equals: query } }
                ]
            },
            take: 5,
            select: {
                id: true,
                title: true,
                price: true,
                images: true,
                category: { select: { icon: true, name: true } }
            }
        });

        return NextResponse.json(ads);
    } catch (error) {
        console.error("Search API Error:", error);
        return NextResponse.json({ message: 'Arama hatası' }, { status: 500 });
    }
}
