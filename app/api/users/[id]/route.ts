import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { getMobileUser } from "@/lib/mobile-auth";

export async function GET(
    request: Request,
    { params }: { params: Promise<{ id: string }> }
) {
    try {
        const { id } = await params;
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

        const user = await prisma.user.findUnique({
            where: { id },
            select: {
                id: true,
                name: true,
                avatar: true,
                createdAt: true,
                phone: true, // Returning phone publicly based on user requirements. A stricter privacy filter can be added here if needed.
                _count: {
                    select: {
                        ads: { where: { status: "ACTIVE" } },
                        friends: true,
                    }
                },
                ads: {
                    where: { status: "ACTIVE" },
                    orderBy: { createdAt: "desc" },
                    include: {
                        category: true,
                        province: true,
                        district: true,
                    }
                }
            }
        }) as any;

        if (!user) {
            return NextResponse.json({ error: "Kullanıcı bulunamadı" }, { status: 404 });
        }

        // Check if the current logged in user is friends with this profile
        let connectionStatus = "NONE";
        let isFriend = false;

        if (userId) {
            if (userId === id) {
                connectionStatus = "SELF";
            } else {
                // Check for block relationship first
                const blockRecord = await prisma.blockedUser.findFirst({
                    where: {
                        OR: [
                            { blockerId: userId, blockedId: id },
                            { blockerId: id, blockedId: userId }
                        ]
                    }
                });

                if (blockRecord) {
                    connectionStatus = blockRecord.blockerId === userId ? "BLOCKED_BY_ME" : "BLOCKED_BY_THEM";
                } else {
                    const friendRecord = await prisma.friend.findUnique({
                        where: {
                            userId_friendId: {
                                userId: userId,
                                friendId: id
                            }
                        }
                    });

                    if (friendRecord) {
                        isFriend = true;
                        connectionStatus = "FRIEND";
                    }
                }
            }
        }

        // Normalize ads output to flat structure typically expected
        const serializedAds = user.ads.map((ad: any) => ({
            ...ad,
            images: ad.images,
        }));

        return NextResponse.json({
            user: {
                id: user.id,
                name: user.name,
                avatar: user.avatar,
                createdAt: user.createdAt,
                phone: user.phone,
                stats: {
                    activeAds: user._count.ads,
                    followers: user._count.friends
                }
            },
            ads: serializedAds,
            connectionStatus,
            isFriend,
        });

    } catch (error) {
        console.error("Fetch user profile error:", error);
        return NextResponse.json(
            { error: "Sunucu hatası oluştu" },
            { status: 500 }
        );
    }
}
