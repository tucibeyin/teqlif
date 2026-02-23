import { NextResponse } from "next/server";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";

export async function GET(request: Request) {
    try {
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        const user = await prisma.user.findUnique({
            where: { id: session.user.id },
            select: { name: true, email: true, phone: true }
        });

        if (!user) {
            return NextResponse.json({ message: "Kullanıcı bulunamadı" }, { status: 404 });
        }

        return NextResponse.json(user);
    } catch (error) {
        console.error("Get Profile Error:", error);
        return NextResponse.json({ message: "Bir hata oluştu" }, { status: 500 });
    }
}

export async function PATCH(request: Request) {
    try {
        const session = await auth();
        if (!session?.user) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        const body = await request.json();
        const { name, email, phone } = body;

        if (!name || !email) {
            return NextResponse.json({ message: "Ad ve E-posta alanları zorunludur" }, { status: 400 });
        }

        // Email uniqueness check if email was changed
        if (email !== session.user.email) {
            const existing = await prisma.user.findUnique({ where: { email } });
            if (existing) {
                return NextResponse.json({ message: "Bu e-posta adresi zaten kullanılıyor" }, { status: 400 });
            }
        }

        const updatedUser = await prisma.user.update({
            where: { id: session.user.id },
            data: { name, email, phone: phone || null }
        });

        return NextResponse.json({
            message: "Profil başarıyla güncellendi",
            user: { name: updatedUser.name, email: updatedUser.email, phone: updatedUser.phone }
        });

    } catch (error) {
        console.error("Update Profile Error:", error);
        return NextResponse.json({ message: "Bir hata oluştu" }, { status: 500 });
    }
}
