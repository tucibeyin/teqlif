import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

export async function DELETE(request: Request) {
    try {
        // getMobileUser supports both NextAuth session (web) and custom JWT (mobile)
        const userSession = await getMobileUser(request);

        if (!userSession?.id) {
            return NextResponse.json({ error: "Yetkisiz erişim" }, { status: 401 });
        }

        // Delete the user — all related data (Ads, Bids, Conversations, Messages,
        // Notifications, Favorites, Friends, FriendLists) cascades automatically
        // as defined in the Prisma schema with onDelete: Cascade.
        await prisma.user.delete({
            where: { id: userSession.id },
        });

        return NextResponse.json({ success: true, message: "Hesabınız başarıyla silindi." });
    } catch (error) {
        console.error("Delete account error:", error);
        return NextResponse.json(
            { error: "Hesap silinirken bir hata oluştu." },
            { status: 500 }
        );
    }
}
