import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { getMobileUser } from "@/lib/mobile-auth";

// POST endpoint to create a new custom friend list
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

        const { name } = await request.json();

        if (!name || name.trim() === "") {
            return NextResponse.json({ error: "Liste adı boş olamaz" }, { status: 400 });
        }

        // Check for duplicates
        const existing = await prisma.friendList.findFirst({
            where: {
                userId: userId,
                name: name.trim()
            }
        });

        if (existing) {
            return NextResponse.json({ error: "Bu isimde bir listeniz zaten var" }, { status: 400 });
        }

        const newList = await prisma.friendList.create({
            data: {
                userId: userId,
                name: name.trim()
            }
        });

        return NextResponse.json({ success: true, message: "Liste oluşturuldu", list: newList }, { status: 201 });

    } catch (error) {
        console.error("Create list error:", error);
        return NextResponse.json({ error: "Sunucu hatası" }, { status: 500 });
    }
}
