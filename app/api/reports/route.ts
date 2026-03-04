import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) {
            return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
        }

        const { reason, reportedUserId, adId } = await request.json();

        if (!reason || reason.trim() === "") {
            return NextResponse.json({ error: "Şikayet sebebi gereklidir." }, { status: 400 });
        }

        if (!reportedUserId && !adId) {
            return NextResponse.json({ error: "Şikayet edilecek bir kullanıcı veya ilan belirtmelisiniz." }, { status: 400 });
        }

        const report = await prisma.report.create({
            data: {
                reason,
                reporterId: currentUser.id,
                reportedUserId: reportedUserId || null,
                adId: adId || null
            }
        });

        return NextResponse.json(report, { status: 201 });
    } catch (error) {
        console.error("POST Report error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
