import { NextRequest, NextResponse } from "next/server";
import { AccessToken } from "livekit-server-sdk";
import { getMobileUser } from "@/lib/mobile-auth";
import { startChannel } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/channel/start
 *
 * Yayıncı kanalını başlatır:
 *   1. Redis'te channel:{hostId}:status = "live" yazar.
 *   2. Host için channel:{hostId} LiveKit odasına yayıncı yetkisiyle token üretir.
 *
 * Response: { token, wsUrl, roomName }
 */
export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const currentUser = await getMobileUser(req);
    if (!currentUser?.id) {
      return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
    }
    const hostId = currentUser.id;

    // ── Env Check ─────────────────────────────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (!apiKey || !apiSecret || !wsUrl) {
      console.error("[channel/start] LiveKit env değişkenleri eksik.");
      return NextResponse.json({ error: "Sunucu yapılandırma hatası." }, { status: 500 });
    }

    // ── Redis: Kanalı Başlat ───────────────────────────────────────────────────
    await startChannel(hostId);

    // ── LiveKit: Host Token Üret ───────────────────────────────────────────────
    // Oda adı = channel:{hostId} — ilanlardan bağımsız, kalıcı yayıncı kanalı.
    const roomName = `channel:${hostId}`;

    const at = new AccessToken(apiKey, apiSecret, {
      identity: hostId,
      name: currentUser.name ?? hostId,
    });

    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canPublishData: true,
      canSubscribe: true,
    });

    const token = await at.toJwt();

    return NextResponse.json({ token, wsUrl, roomName }, { status: 200 });
  } catch (err) {
    console.error("[channel/start] Hata:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
