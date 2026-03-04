import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getMobileUser } from "@/lib/mobile-auth";

// GET: Check if a user is blocked by the current user
export async function GET(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

        const { searchParams } = new URL(request.url);
        const targetUserId = searchParams.get('userId');

        if (!targetUserId) {
            return NextResponse.json({ error: "Missing userId" }, { status: 400 });
        }

        const blockRecord = await prisma.blockedUser.findUnique({
            where: {
                blockerId_blockedId: {
                    blockerId: currentUser.id,
                    blockedId: targetUserId
                }
            }
        });

        return NextResponse.json({ isBlocked: !!blockRecord });
    } catch (error) {
        console.error("GET Block status error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}

// POST: Block a user
export async function POST(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

        const { targetUserId } = await request.json();

        if (!targetUserId) {
            return NextResponse.json({ error: "Missing targetUserId" }, { status: 400 });
        }

        if (currentUser.id === targetUserId) {
            return NextResponse.json({ error: "Kendinizi engelleyemezsiniz" }, { status: 400 });
        }

        // Create block record
        const block = await prisma.blockedUser.upsert({
            where: {
                blockerId_blockedId: {
                    blockerId: currentUser.id,
                    blockedId: targetUserId
                }
            },
            update: {}, // Do nothing if already exists
            create: {
                blockerId: currentUser.id,
                blockedId: targetUserId
            }
        });

        // Optional: Remove any existing friend relationships when blocked
        await prisma.friend.deleteMany({
            where: {
                OR: [
                    { userId: currentUser.id, friendId: targetUserId },
                    { userId: targetUserId, friendId: currentUser.id }
                ]
            }
        });

        return NextResponse.json(block, { status: 201 });
    } catch (error) {
        console.error("POST Block user error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}

// DELETE: Unblock a user
export async function DELETE(request: Request) {
    try {
        const currentUser = await getMobileUser(request);
        if (!currentUser) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

        const { searchParams } = new URL(request.url);
        const targetUserId = searchParams.get('userId');

        if (!targetUserId) {
            return NextResponse.json({ error: "Missing userId" }, { status: 400 });
        }

        await prisma.blockedUser.deleteMany({
            where: {
                blockerId: currentUser.id,
                blockedId: targetUserId
            }
        });

        return NextResponse.json({ success: true });
    } catch (error) {
        console.error("DELETE Unblock user error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
