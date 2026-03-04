import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";

export async function DELETE() {
    try {
        const session = await auth();

        if (!session?.user?.id) {
            return NextResponse.json({ error: "Yetkisiz erişim" }, { status: 401 });
        }

        const userId = session.user.id;

        // Delete the user — all related data (Ads, Bids, Conversations, Messages,
        // Notifications, Favorites, Friends, FriendLists) will cascade automatically
        // as defined in the Prisma schema with onDelete: Cascade.
        await prisma.user.delete({
            where: { id: userId },
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
