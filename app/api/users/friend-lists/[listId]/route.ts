import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";

// PATCH endpoint to assign or remove a friend from a custom list
export async function PATCH(
    request: Request,
    { params }: { params: Promise<{ listId: string }> }
) {
    try {
        const { listId } = await params;
        const session = await auth();
        if (!session?.user?.id) {
            return NextResponse.json({ error: "Yetkisiz oturum" }, { status: 401 });
        } const { friendId } = await request.json();

        if (!friendId) {
            return NextResponse.json({ error: "Arkadaş ID'si eksik" }, { status: 400 });
        }

        // Verify the list belongs to the user or is 'null' to remove them from a list
        if (listId !== 'null') {
            const list = await prisma.friendList.findUnique({
                where: { id: listId }
            });

            if (!list || list.userId !== session.user.id) {
                return NextResponse.json({ error: "Liste bulunamadı veya yetkisiz erişim" }, { status: 403 });
            }
        }

        // Update the friend's list association
        const updatedFriend = await prisma.friend.update({
            where: {
                userId_friendId: {
                    userId: session.user.id,
                    friendId: friendId
                }
            },
            data: {
                friendListId: listId === 'null' ? null : listId
            }
        });

        return NextResponse.json({ success: true, message: "Liste güncellendi", friend: updatedFriend });

    } catch (error) {
        console.error("Assign list error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}

// DELETE endpoint to remove a custom list entirely
export async function DELETE(
    request: Request,
    { params }: { params: Promise<{ listId: string }> }
) {
    try {
        const { listId } = await params;
        const session = await auth();
        if (!session?.user?.id) {
            return NextResponse.json({ error: "Yetkisiz oturum" }, { status: 401 });
        }

        const list = await prisma.friendList.findUnique({
            where: { id: listId }
        });

        if (!list || list.userId !== session.user.id) {
            return NextResponse.json({ error: "Liste bulunamadı veya yetkisiz erişim" }, { status: 403 });
        }

        // Deleting the list will cascade set null to friends linked to it due to `@relation(onDelete: SetNull)`
        await prisma.friendList.delete({
            where: { id: listId }
        });

        return NextResponse.json({ success: true, message: "Liste silindi" });

    } catch (error) {
        console.error("Delete list error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
