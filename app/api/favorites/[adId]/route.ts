import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';

// DELETE target favorite
export async function DELETE(
    request: Request,
    { params }: { params: Promise<{ adId: string }> }
) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser?.id) {
            return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
        }

        const p = await params;

        // Try to delete by composite unique key
        await prisma.favorite.deleteMany({
            where: {
                userId: currentUser.id,
                adId: p.adId,
            }
        });

        return NextResponse.json({ success: true });
    } catch (error) {
        console.error('Delete Favorite Error:', error);
        return NextResponse.json(
            { message: 'Favori silinirken hata oluştu' },
            { status: 500 }
        );
    }
}
