import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

export async function POST(req: Request) {
    try {
        const currentUser = await getMobileUser(req);
        if (!currentUser) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        const userId = currentUser.id;

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
