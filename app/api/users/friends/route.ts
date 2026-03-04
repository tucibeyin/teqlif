import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { getMobileUser } from "@/lib/mobile-auth";

// GET endpoints allows fetching the logged-in user's friend list with optional list grouping
export async function GET(request: Request) {
    try {
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

        const user = await prisma.user.findUnique({
            where: { id: userId }
        });

        if (!user) {
            return NextResponse.json({ error: "Kullanıcı bulunamadı" }, { status: 404 });
        }

        const friendsData = await prisma.friend.findMany({
            where: { userId: user.id },
            include: {
                friend: {
                    select: {
                        id: true,
                        name: true,
                        avatar: true,
                        phone: true,
                    }
                },
                friendList: true
            },
            orderBy: { createdAt: 'desc' }
        });

        // Grouping
        const allFriends = friendsData.map(f => ({
            id: f.friend.id,
            name: f.friend.name,
            avatar: f.friend.avatar,
            phone: f.friend.phone,
            friendListId: f.friendListId,
            friendListName: f.friendList?.name,
            addedAt: f.createdAt
        }));

        const friendListsData = await prisma.friendList.findMany({
            where: { userId: user.id },
            orderBy: { name: 'asc' }
        });

        return NextResponse.json({
            friends: allFriends,
            customLists: friendListsData.map(l => ({ id: l.id, name: l.name }))
        });

    } catch (error) {
        console.error("Fetch friends error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}

// POST endpoint to add a friend (follow)
export async function POST(request: Request) {
    try {
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
            return NextResponse.json({ error: "Lütfen giriş yapın" }, { status: 401 });
        }

        const { targetUserId } = await request.json();

        if (!targetUserId) {
            return NextResponse.json({ error: "Hedef kullanıcı ID'si eksik" }, { status: 400 });
        }

        if (userId === targetUserId) {
            return NextResponse.json({ error: "Kendinizi takip edemezsiniz" }, { status: 400 });
        }

        // Check if already friends
        const existing = await prisma.friend.findUnique({
            where: {
                userId_friendId: {
                    userId: userId,
                    friendId: targetUserId
                }
            }
        });

        if (existing) {
            return NextResponse.json({ message: "Zaten arkadaşsınız" }, { status: 200 });
        }

        const newFriend = await prisma.friend.create({
            data: {
                userId: userId,
                friendId: targetUserId
            }
        });

        return NextResponse.json({ success: true, message: "Arkadaş eklendi", relationship: newFriend }, { status: 201 });

    } catch (error) {
        console.error("Add friend error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
