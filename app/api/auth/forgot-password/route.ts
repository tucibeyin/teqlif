import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendPasswordResetEmail } from "@/lib/mail";

export async function POST(req: NextRequest) {
    try {
        const { email } = await req.json();

        if (!email) {
            return NextResponse.json({ error: "Email zorunludur." }, { status: 400 });
        }

        const user = await prisma.user.findUnique({ where: { email } });

        if (!user) {
            // To prevent email enumeration attacks, always return success even if user doesn't exist.
            return NextResponse.json({ message: "Sıfırlama kodu gönderildi." }, { status: 200 });
        }

        // Generate a 6-digit reset code
        const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
        // Expiration in 15 minutes
        const resetCodeExpires = new Date(Date.now() + 15 * 60 * 1000);

        await prisma.user.update({
            where: { id: user.id },
            data: {
                resetCode,
                resetCodeExpires,
            },
        });

        await sendPasswordResetEmail(user.email, resetCode);

        return NextResponse.json({ message: "Sıfırlama kodu gönderildi." }, { status: 200 });
    } catch (err) {
        console.error("Forgot password error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
