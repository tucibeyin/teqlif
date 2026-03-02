import { NextRequest, NextResponse } from 'next/server';
import { AccessToken } from 'livekit-server-sdk';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';

export async function GET(req: NextRequest) {
  try {
    const session = await auth();
    // Kullanıcı oturumu kontrolü
    if (!session || !session.user || !session.user.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const userId = session.user.id;
    const userName = session.user.name || 'Anonymous';

    // İstek parametrelerini al
    const room = req.nextUrl.searchParams.get('room');
    const roleParam = req.nextUrl.searchParams.get('role'); // İleriki co-host (guest) özelliği için

    if (!room) {
      return NextResponse.json({ error: 'Room (Ad ID) is required' }, { status: 400 });
    }

    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;

    if (!apiKey || !apiSecret) {
      console.error('[LiveKit Token] API Keys missing');
      return NextResponse.json({ error: 'Server misconfigured: Keys missing' }, { status: 500 });
    }

    // Prisma üzerinden ilanı bul
    const ad = await prisma.ad.findUnique({
      where: { id: room },
      select: { userId: true }
    });

    if (!ad) {
      return NextResponse.json({ error: 'Ad not found' }, { status: 404 });
    }

    // Rol Belirleme
    const isHost = ad.userId === userId;
    const isGuest = roleParam === 'guest'; // Co-Host daveti almış izleyici

    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
      name: userName,
    });

    // İzinler (Bouncer Logic)
    // Sadece Host veya Davetli Guest yayın (kamera/mikrofon) açabilir
    const canPublish = isHost || isGuest;
    // Herkes yayını izleyebilir
    const canSubscribe = true;
    // Herkes Data Channel kullanabilir (Teklif vermek ve Ephemeral Chat için KRİTİK)
    const canPublishData = true;

    at.addGrant({
      roomJoin: true,
      room: room,
      canPublish,
      canSubscribe,
      canPublishData,
    });

    return NextResponse.json({ token: await at.toJwt() });
  } catch (error: any) {
    console.error('[LiveKit Token API] Processing error:', error);
    return NextResponse.json({ error: 'Failed to generate token' }, { status: 500 });
  }
}
