import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import { roomService } from "@/lib/livekit";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(req: NextRequest) {
    try {
        // 1. Session check
        const session = await auth();
        let userId = session?.user?.id;

        // Support Mobile Auth as well
        if (!userId) {
            const mobileUser = await getMobileUser(req);
            if (mobileUser) {
                userId = mobileUser.id;
            }
        }

        if (!userId) {
            return NextResponse.json({ error: "Giriş yapmanız gerekiyor." }, { status: 401 });
        }

        // 2. Parse body
        const body = await req.json();
        const { roomId, identity, action } = body;

        if (!roomId || !identity || !action) {
            return NextResponse.json({ error: "roomId, identity ve action zorunludur." }, { status: 400 });
        }

        // 3. Ownership verification
        // Kanal modu: roomId = "channel:{hostId}" — Prisma değil, string'den sahip çıkarılır.
        // Klasik mod: roomId = adId — Prisma ile doğrulanır.
        let callerIsOwner = false;
        let effectiveRoom = roomId;

        if (roomId.startsWith("channel:")) {
            const channelHostId = roomId.replace("channel:", "");
            callerIsOwner = channelHostId === userId;
        } else {
            const ad = await prisma.ad.findUnique({
                where: { id: roomId },
                select: { userId: true },
            });
            if (!ad) {
                return NextResponse.json({ error: "İlan bulunamadı." }, { status: 404 });
            }
            callerIsOwner = ad.userId === userId;
            // Klasik modda yayın channel:{hostId} odasında olabilir; roomId=adId geçilmişse kullan
            effectiveRoom = roomId;
        }

        if (!callerIsOwner) {
            return NextResponse.json({ error: "Bu işlemi gerçekleştirme yetkiniz yok (Owner only)." }, { status: 403 });
        }

        // 4. Perform moderation action
        if (action === 'kick') {
            await roomService.removeParticipant(effectiveRoom, identity);
        } else if (action === 'mute') {
            // Revoke publishData permission to prevent chat
            await roomService.updateParticipant(effectiveRoom, identity, undefined, {
                canPublish: true,
                canSubscribe: true,
                canPublishData: false,
            });
        } else {
            return NextResponse.json({ error: "Geçersiz işlem tipi." }, { status: 400 });
        }

        return NextResponse.json({ success: true, action });

    } catch (err: any) {
        console.error("POST /api/livekit/moderate error:", err);
        return NextResponse.json({ error: "Sunucu hatası: " + (err.message || "Bilinmeyen hata") }, { status: 500 });
    }
}
