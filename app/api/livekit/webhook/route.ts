import { NextRequest, NextResponse } from 'next/server';
import { WebhookReceiver } from 'livekit-server-sdk';
import { prisma } from '@/lib/prisma';
import { sendPushNotification } from '@/lib/fcm';

// Sadece bu eventleri dikkate alacağız
const ALLOWED_EVENTS = ['room_started', 'room_finished'];

export async function POST(req: NextRequest) {
    try {
        const body = await req.text();
        const authHeader = req.headers.get('authorization');

        if (!authHeader) {
            return NextResponse.json({ error: 'Missing authorization header' }, { status: 401 });
        }

        const apiKey = process.env.LIVEKIT_API_KEY;
        const apiSecret = process.env.LIVEKIT_API_SECRET;

        if (!apiKey || !apiSecret) {
            console.error('[LiveKit Webhook] Missing API keys in environment');
            return NextResponse.json({ error: 'Server configuration error' }, { status: 500 });
        }

        const receiver = new WebhookReceiver(apiKey, apiSecret);
        const event = await receiver.receive(body, authHeader);

        if (!event || !event.event) {
            return NextResponse.json({ error: 'Invalid webhook event format' }, { status: 400 });
        }

        console.log(`[LiveKit Webhook] Received event: ${event.event} for room: ${event.room?.name}`);

        if (!ALLOWED_EVENTS.includes(event.event)) {
            return NextResponse.json({ message: 'Event ignored' }, { status: 200 });
        }

        // Room name MUST be the adId in our architecture
        const adId = event.room?.name;

        if (!adId) {
            console.error('[LiveKit Webhook] Room name (adId) is missing in the event');
            return NextResponse.json({ error: 'Room name missing' }, { status: 400 });
        }

        // --- ROOM STARTED ---
        if (event.event === 'room_started') {
            const updatedAd = await prisma.ad.update({
                where: { id: adId },
                data: {
                    isLive: true,
                    liveKitRoomId: event.room?.sid // Opsiyonel referans
                },
                include: {
                    favorites: {
                        include: { user: true }
                    }
                }
            });

            console.log(`[LiveKit Webhook] Ad ${adId} is now LIVE.`);

            // Favorileyen kullanıcılara Push Notification atalım
            const favoritedUsers = updatedAd.favorites.map(f => f.user).filter(u => u.fcmToken);

            if (favoritedUsers.length > 0) {
                const title = '🔥 Canlı Yayın Başladı!';
                const bodyMsg = `${updatedAd.title} için canlı mezat şu an yayında! Hemen katılın.`;

                // Asenkron olarak gönderelim, webhook'u bekletmeyelim
                Promise.all(favoritedUsers.map(user =>
                    sendPushNotification(user.fcmToken!, title, bodyMsg, { adId: updatedAd.id, type: 'LIVE_AUCTION_STARTED' })
                )).catch(err => console.error('[LiveKit Webhook] Error sending FCM push:', err));

                console.log(`[LiveKit Webhook] Sent push notifications to ${favoritedUsers.length} users.`);
            }
        }

        // --- ROOM FINISHED ---
        if (event.event === 'room_finished') {
            await prisma.ad.update({
                where: { id: adId },
                data: { isLive: false }
            });
            console.log(`[LiveKit Webhook] Ad ${adId} is no longer live.`);
        }

        return NextResponse.json({ success: true }, { status: 200 });
    } catch (error: any) {
        console.error('[LiveKit Webhook] Processing error:', error);
        return NextResponse.json({ error: 'Internal server error', details: error.message }, { status: 500 });
    }
}
