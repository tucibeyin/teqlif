import { NextRequest, NextResponse } from "next/server";
import { DataPacket_Kind } from "livekit-server-sdk";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";
import { roomService, broadcastToRoom } from "@/lib/livekit";

export const dynamic = "force-dynamic";

type StageAction = "invite" | "accept" | "revoke";

export async function POST(req: NextRequest) {
    try {
        const caller = await getMobileUser(req);
        if (!caller?.id) {
            return NextResponse.json(
                { error: "Giriş yapmanız gerekiyor." },
                { status: 401 }
            );
        }

        const body = await req.json();
        const { adId, targetIdentity, action } = body as {
            adId: string;
            targetIdentity: string;
            action: StageAction;
        };

        if (!adId || !targetIdentity || !action) {
            return NextResponse.json(
                { error: "adId, targetIdentity ve action zorunludur." },
                { status: 400 }
            );
        }

        if (!["invite", "accept", "revoke"].includes(action)) {
            return NextResponse.json(
                { error: "Geçersiz action. invite | accept | revoke olmalıdır." },
                { status: 400 }
            );
        }

        const ad = await prisma.ad.findUnique({ where: { id: adId } });
        if (!ad) {
            return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
        }

        // LiveKit room name: prefer stored liveKitRoomId, fallback to adId
        const roomName = (ad as any).liveKitRoomId ?? adId;

        const isHost = ad.userId === caller.id;
        const isSelf = targetIdentity === caller.id;

        // ── Authorization ────────────────────────────────────────────────────
        if (action === "invite" && !isHost) {
            return NextResponse.json(
                { error: "Sadece yayıncı sahneye davet gönderebilir." },
                { status: 403 }
            );
        }
        if (action === "accept" && !isSelf) {
            return NextResponse.json(
                { error: "Yalnızca davet edilen kişi kabul edebilir." },
                { status: 403 }
            );
        }
        if (action === "revoke" && !isHost && !isSelf) {
            return NextResponse.json(
                { error: "Bu işlem için yetkiniz yok." },
                { status: 403 }
            );
        }

        // ── Action Handlers ──────────────────────────────────────────────────
        if (action === "invite") {
            // Send a targeted DataChannel signal to the invitee only.
            // No permission change yet — the participant accepts first.
            const payload = new TextEncoder().encode(
                JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity })
            );
            await roomService.sendData(roomName, payload, DataPacket_Kind.RELIABLE, {
                destinationIdentities: [targetIdentity],
            });
        } else if (action === "accept") {
            // Grant publish permissions in-place — no disconnect/reconnect needed.
            await roomService.updateParticipant(roomName, targetIdentity, {
                permission: {
                    canPublish: true,
                    canSubscribe: true,
                    canPublishData: true,
                },
            });

            // Notify everyone so UIs can render the new PiP tile immediately.
            await broadcastToRoom(
                roomName,
                JSON.stringify({
                    type: "STAGE_UPDATE",
                    action: "joined",
                    identity: targetIdentity,
                })
            );
        } else if (action === "revoke") {
            // Revoke publish permissions in-place.
            await roomService.updateParticipant(roomName, targetIdentity, {
                permission: {
                    canPublish: false,
                    canSubscribe: true,
                    canPublishData: true,
                },
            });

            // Notify everyone so UIs can remove the PiP tile.
            await broadcastToRoom(
                roomName,
                JSON.stringify({
                    type: "STAGE_UPDATE",
                    action: "left",
                    identity: targetIdentity,
                })
            );
        }

        return NextResponse.json({ success: true });
    } catch (e: any) {
        console.error("[Stage API] Error:", e);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
