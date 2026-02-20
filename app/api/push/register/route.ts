import { NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.AUTH_SECRET || "fallback-secret-change-me";

function verifyMobileToken(authHeader: string | null) {
    if (!authHeader?.startsWith("Bearer ")) return null;
    try {
        return jwt.verify(authHeader.slice(7), JWT_SECRET) as { id: string };
    } catch {
        return null;
    }
}

export async function POST(req: Request) {
    try {
        // Support both web session and mobile JWT
        const session = await auth();
        const authHeader = req.headers.get("authorization");
        const mobilePayload = verifyMobileToken(authHeader);

        const userId = session?.user?.id ?? mobilePayload?.id;

        if (!userId) {
            return NextResponse.json({ message: "Yetkisiz erişim" }, { status: 401 });
        }

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
