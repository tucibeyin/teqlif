import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { getMobileUser } from "@/lib/mobile-auth";

// DELETE endpoint to unfollow / remove a friend
export async function DELETE(
    request: Request,
    { params }: { params: Promise<{ friendId: string }> }
) {
    try {
        const { friendId } = await params;
        let userId: string | undefined;

        // Try Mobile Token Auth First
        const mobileUser = await getMobileUser(request);
        if (mobileUser) {
            userId = mobileUser.id;
        } else {
            // Fallback to Web Session
            const session = await auth();
            userId = session?.user?.id;
        }

        if (!userId) {
            return NextResponse.json({ error: "Yetkisiz oturum" }, { status: 401 });
        }



        if (!friendId) {
            return NextResponse.json({ error: "Hedef kullanıcı ID'si eksik" }, { status: 400 });
        }

        // Delete the friend relationship
        await prisma.friend.deleteMany({
            where: {
                userId: userId,
                friendId: friendId
            }
        });

        return NextResponse.json({ success: true, message: "Arkadaşlıktan çıkarıldı" });

    } catch (error) {
        console.error("Remove friend error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
