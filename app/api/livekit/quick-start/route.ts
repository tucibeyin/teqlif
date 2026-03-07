import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { getMobileUser } from "@/lib/mobile-auth";
import { startChannel } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

/**
 * POST /api/livekit/quick-start
 *
 * Host "Canlı Yayın Başlat" butonuna bastığında tetiklenir.
 * Ghost Ad mantığı kaldırıldı. Kanal boş başlar; ürünler ITEM_PINNED ile eklenir.
 *
 * Akış:
 *  1. Auth
 *  2. Redis: startChannel → channel:{userId}:status = "live", active_ad temizlenir
 *  3. LiveKit: CHANNEL_STARTED sinyali
 *  4. { success, roomName, hostId } dön
 */
export async function POST(req: NextRequest) {
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const currentUser = await getMobileUser(req);
    if (!currentUser?.id) {
      return NextResponse.json(
        { error: "Giriş yapmanız gerekiyor." },
        { status: 401 }
      );
    }

    // ── Redis: Kanalı Başlat ──────────────────────────────────────────────────
    await startChannel(currentUser.id);

    const channelRoom = `channel:${currentUser.id}`;

    // ── LiveKit: CHANNEL_STARTED Sinyali ─────────────────────────────────────
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (apiKey && apiSecret && wsUrl) {
      const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
      const payload = JSON.stringify({
        type: "CHANNEL_STARTED",
        hostId: currentUser.id,
      });

      roomService
        .sendData(channelRoom, new TextEncoder().encode(payload), 1)
        .catch((err) =>
          console.error("[CHANNEL_STARTED] LiveKit broadcast error:", err)
        );
    } else {
      console.warn("[CHANNEL_STARTED] LiveKit env variables missing — skipping broadcast");
    }

    return NextResponse.json(
      { success: true, roomName: channelRoom, hostId: currentUser.id },
      { status: 200 }
    );
  } catch (err) {
    console.error("POST /api/livekit/quick-start error:", err);
    return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
  }
}
