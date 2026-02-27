import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(req: Request) {
    try {
        const currentUser = await getMobileUser(req);

        if (!currentUser) {
            return NextResponse.json({ message: "Yetkisiz erişim" }, { status: 401 });
        }

        const userId = currentUser.id;

        const { fcmToken } = await req.json();
        if (!fcmToken) {
            return NextResponse.json({ message: "FCM token zorunlu" }, { status: 400 });
        }

        await prisma.user.update({
            where: { id: userId },
            data: { fcmToken },
        });

        return NextResponse.json({ success: true });
    } catch (error) {
        console.error("Push Register Error:", error);
        return NextResponse.json({ message: "Sunucu hatası" }, { status: 500 });
    }
}
