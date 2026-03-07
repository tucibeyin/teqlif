import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(req: NextRequest) {
    try {
        const user = await getMobileUser(req);
        if (!user?.id) {
            return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
        }

        const body = await req.json();
        const { adId, targetIdentity, signal } = body;

        if (!adId || !targetIdentity || !signal) {
            return NextResponse.json({ error: "Missing parameters" }, { status: 400 });
        }

        const ad = await prisma.ad.findUnique({ where: { id: adId } });
        if (!ad || !ad.liveKitRoomId) {
            return NextResponse.json({ error: "Room not found" }, { status: 404 });
        }

        // Only the host can invite or kick
        if (ad.userId !== user.id && signal !== "ACCEPT_INVITE" && signal !== "REJECT_INVITE") {
            return NextResponse.json({ error: "Not the host" }, { status: 403 });
        }

        const apiKey = process.env.LIVEKIT_API_KEY;
        const apiSecret = process.env.LIVEKIT_API_SECRET;
        const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

        if (!apiKey || !apiSecret || !wsUrl) {
            return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
        }

        const roomService = new RoomServiceClient(wsUrl, apiKey, apiSecret);

        // signal is one of: "INVITE_TO_STAGE", "KICK_FROM_STAGE"
        const payload = JSON.stringify({ type: signal, targetIdentity });
        const data = new TextEncoder().encode(payload);

        const roomName = `channel:${ad.userId}`;

        // Send to specific target or broadcast to room
        if (targetIdentity === "BROADCAST") {
            await roomService.sendData(roomName, data, 1, []);
        } else {
            await roomService.sendData(roomName, data, 1, [targetIdentity]);
        }

        return NextResponse.json({ success: true, message: "Signal sent" });
    } catch (e: any) {
        console.error("LiveKit Signal error:", e);
        return NextResponse.json({ error: "Failed to send signal" }, { status: 500 });
    }
}
