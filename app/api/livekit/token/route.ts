import { NextRequest, NextResponse } from 'next/server';
import { AccessToken } from 'livekit-server-sdk';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';
import { logger } from '@/lib/logger';

export async function GET(req: NextRequest) {
  try {
    const session = await auth();
    let userId = session?.user?.id;
    let userName = session?.user?.name || 'Anonymous';

    // Support Mobile Auth
    if (!userId) {
      const mobileUser = await getMobileUser(req);
      if (mobileUser) {
        userId = mobileUser.id;
        userName = mobileUser.name || 'Mobile User';
      }
    }

    if (!userId) {
      logger.liveKit("WARN", "TOKEN_API", "Unauthorized attempt to get token");
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

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
      logger.liveKit("WARN", "TOKEN_API", `Ad not found for room: ${room}`);
      return NextResponse.json({ error: 'Ad not found' }, { status: 404 });
    }

    // Rol Belirleme
    const isHost = ad.userId === userId;
    const isGuest = roleParam === 'guest'; // Co-Host daveti almış izleyici

    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
      name: userName,
    });

    const canPublish = isHost || isGuest;

    at.addGrant({
      roomJoin: true,
      room: room,
      canPublish: canPublish,
      canPublishData: true,
      canSubscribe: true,
    });

    const token = await at.toJwt();
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    logger.liveKit("INFO", "TOKEN_API", `Generated token for user ${userId} in room ${room} (isHost: ${isHost})`);
    return NextResponse.json({ token, wsUrl });
  } catch (error: any) {
    console.error('[LiveKit Token API] Processing error:', error);
    return NextResponse.json({ error: 'Failed to generate token' }, { status: 500 });
  }
}
