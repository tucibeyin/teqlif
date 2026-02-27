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
        const session = await auth();
        const authHeader = req.headers.get("authorization");
        const mobilePayload = verifyMobileToken(authHeader);

        const userId = session?.user?.id ?? mobilePayload?.id;
        if (!userId) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        // Clear FCM token so user no longer receives push notifications
        await prisma.user.update({
            where: { id: userId },
            data: { fcmToken: null },
        });

        return NextResponse.json({ success: true });
    } catch (error) {
        console.error("Push Unregister Error:", error);
        return NextResponse.json({ message: "Server error" }, { status: 500 });
    }
}
