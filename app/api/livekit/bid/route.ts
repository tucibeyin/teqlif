import { NextRequest, NextResponse } from 'next/server';
import { RoomServiceClient } from 'livekit-server-sdk';
import { auth } from '@/auth';
import { placeLiveBid } from '@/lib/redis';

export async function POST(req: NextRequest) {
    try {
        const session = await auth();
        if (!session || !session.user || !session.user.id) {
            return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
        }

        const userId = session.user.id;
        const body = await req.json();
        const { roomId, amount } = body;

        if (!roomId || !amount || typeof amount !== 'number') {
            return NextResponse.json({ error: 'Invalid input' }, { status: 400 });
        }

        // Redis üzerinde atomik fiyat kontrolü ve kayıt
        const bidResult = await placeLiveBid(roomId, userId, amount);

        if (bidResult === 1) {
            // Teqlif kabul edildi! Şimdi tüm odaya (Data Channel) broadcast yapalım.
            const apiKey = process.env.LIVEKIT_API_KEY;
            const apiSecret = process.env.LIVEKIT_API_SECRET;
            const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

            if (!apiKey || !apiSecret || !wsUrl) {
                console.error('[LiveKit Bid API] Keys or URL missing');
                return NextResponse.json({ error: 'Server config error' }, { status: 500 });
            }

            const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);

            const payload = JSON.stringify({
                type: 'NEW_BID',
                amount: amount,
                userId: userId,
                userName: session.user.name || 'Bidder',
                timestamp: Date.now()
            });

            // Veriyi odaya (room) yolla, topic olarak "auction_events" kullanıyoruz
            await roomService.sendData(
                roomId,
                new TextEncoder().encode(payload),
                1, // Reliability: 1 = RELIABLE (UDP üzerinden ama kayıpsız)
                { topic: 'auction_events' }
            );

            return NextResponse.json({ success: true, message: 'Bid accepted and broadcasted' }, { status: 200 });
        } else {
            return NextResponse.json({ success: false, message: 'Bid was too low' }, { status: 400 });
        }
    } catch (error: any) {
        console.error('[LiveKit Bid API] Processing error:', error);
        return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
    }
}
