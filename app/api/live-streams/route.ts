import { NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getChannelTitle } from "@/lib/services/auction-redis.service";

export const dynamic = "force-dynamic";

export type LiveStreamItem =
  | {
      type: "channel";
      roomId: string;
      hostId: string;
      hostName: string;
      title: string;
      imageUrl: string | null;
      viewerCount: number;
    }
  | {
      type: "ad";
      roomId: string;
      adId: string;
      hostName: string;
      title: string;
      imageUrl: string | null;
      viewerCount: number;
    };

export async function GET() {
  try {
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

    if (!apiKey || !apiSecret || !wsUrl) {
      return NextResponse.json({ streams: [] });
    }

    const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);
    const rooms = await roomService.listRooms();

    const streams = (
      await Promise.all(
        rooms.map(async (room): Promise<LiveStreamItem | null> => {
          if (room.name.startsWith("channel:")) {
            const hostId = room.name.split(":")[1];
            if (!hostId) return null;

            const [user, customTitle] = await Promise.all([
              prisma.user.findUnique({
                where: { id: hostId },
                select: { id: true, name: true, avatar: true },
              }),
              getChannelTitle(hostId),
            ]);
            if (!user) return null;

            return {
              type: "channel",
              roomId: room.name,
              hostId: user.id,
              hostName: user.name ?? "Yayıncı",
              title: customTitle || `${user.name ?? "Yayıncı"} Yayında`,
              imageUrl: user.avatar ?? null,
              viewerCount: room.numParticipants,
            };
          } else {
            const ad = await prisma.ad.findUnique({
              where: { id: room.name },
              select: {
                id: true,
                title: true,
                images: true,
                user: { select: { name: true } },
              },
            });
            if (!ad) return null;

            return {
              type: "ad",
              roomId: room.name,
              adId: ad.id,
              hostName: ad.user.name ?? "Yayıncı",
              title: ad.title,
              imageUrl: ad.images[0] ?? null,
              viewerCount: room.numParticipants,
            };
          }
        })
      )
    ).filter((s): s is LiveStreamItem => s !== null);

    return NextResponse.json({ streams });
  } catch (err) {
    console.error("[GET /api/live-streams] error:", err);
    return NextResponse.json({ streams: [] });
  }
}
