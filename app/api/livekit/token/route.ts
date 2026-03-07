import { NextRequest, NextResponse } from 'next/server';
import { AccessToken } from 'livekit-server-sdk';
import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';
import { getMobileUser } from '@/lib/mobile-auth';
import { logger } from '@/lib/logger';
import { getChannelState } from '@/lib/services/auction-redis.service';

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

    logger.liveKit("INFO", "TOKEN_API", `Request for room: ${room}, role: ${roleParam}`);

    if (!room) {
      return NextResponse.json({ error: 'Room (Ad ID or Channel) is required' }, { status: 400 });
    }

    // ── ODA TİPİ ANALİZİ (Channel vs Ad) ───────────────────────────────────
    let effectiveRoom = room; // Gateway redirect sonrası gerçek oda adı
    let hostIdOfRoom: string | null = null;
    let isChannelRoom = false;

    if (room.startsWith('channel:')) {
      isChannelRoom = true;
      hostIdOfRoom = room.replace('channel:', '');
      logger.liveKit("INFO", "TOKEN_API", `Channel room detected. HostId: ${hostIdOfRoom}`);
    }

    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;

    if (!apiKey || !apiSecret) {
      console.error('[LiveKit Token] API Keys missing');
      return NextResponse.json({ error: 'Server misconfigured: Keys missing' }, { status: 500 });
    }

    // Prisma üzerinden ilanı veya kullanıcıyı doğrula
    if (!isChannelRoom) {
      const ad = await prisma.ad.findUnique({
        where: { id: room },
        select: { userId: true }
      });

      if (!ad) {
        logger.liveKit("WARN", "TOKEN_API", `Ad not found for room: ${room}`);
        return NextResponse.json({ error: 'Ad not found' }, { status: 404 });
      }
      hostIdOfRoom = ad.userId;

      // ── Gateway: Satıcının aktif kanalı varsa o odaya yönlendir ─────────────
      // Viewer, eski usül adId ile gelirse bile channel:{hostId} odasına bağlanır.
      try {
        const channelState = await getChannelState(hostIdOfRoom);
        if (channelState.status === 'live') {
          logger.liveKit("INFO", "TOKEN_API", `Gateway redirect: ad=${room} → channel:${hostIdOfRoom}`);
          effectiveRoom = `channel:${hostIdOfRoom}`;
          isChannelRoom = true;
        }
      } catch (_) {
        // Redis erişilemiyorsa klasik adId odasıyla devam et
      }
    } else {
      // Kanal odası: Prisma yerine Redis'ten canlı olup olmadığını kontrol et.
      const channelState = await getChannelState(hostIdOfRoom!);
      if (channelState.status !== 'live') {
        logger.liveKit("WARN", "TOKEN_API", `Channel not live for hostId: ${hostIdOfRoom}`);
        return NextResponse.json({ error: 'Kanal şu an canlı değil' }, { status: 404 });
      }
    }

    // Rol Belirleme — isHost kontrolü kesin; izleyiciler asla publish edemez.
    // Not: sahneye davet (guest/co-host) yetkisi token'dan değil, stage API'nin
    // roomService.updateParticipant çağrısından (sunucu tarafı) alınır.
    const isHost = hostIdOfRoom === userId;

    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
      name: userName,
    });

    at.addGrant({
      roomJoin: true,
      room: effectiveRoom,
      canPublish: isHost,          // Sadece host yayınlayabilir
      canPublishData: true,        // Herkes data (chat/bid) gönderebilir
      canSubscribe: true,
    });

    const token = await at.toJwt();
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    logger.liveKit("INFO", "TOKEN_API", `Generated token for user ${userId} in room ${effectiveRoom} (isHost: ${isHost})`);
    return NextResponse.json({ token, wsUrl, roomName: effectiveRoom });
  } catch (error: any) {
    console.error('[LiveKit Token API] Processing error:', error);
    return NextResponse.json({ error: 'Failed to generate token' }, { status: 500 });
  }
}
