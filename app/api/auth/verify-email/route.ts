import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function POST(req: NextRequest) {
    try {
        const { email, code } = await req.json();

        if (!email || !code) {
            return NextResponse.json({ error: "Email ve kod zorunludur." }, { status: 400 });
        }

        const user = await prisma.user.findUnique({ where: { email } });

        if (!user) {
            return NextResponse.json({ error: "Kullanıcı bulunamadı." }, { status: 404 });
        }

        if (user.isVerified) {
            return NextResponse.json({ message: "Hesabınız zaten doğrulanmış." }, { status: 200 });
        }

        if (user.verifyCode !== code) {
            return NextResponse.json({ error: "Geçersiz doğrulama kodu." }, { status: 400 });
        }

        if (user.verifyCodeExpires && new Date(user.verifyCodeExpires) < new Date()) {
            return NextResponse.json({ error: "Doğrulama kodunun süresi dolmuş." }, { status: 400 });
        }

        // Verify user and clear verification tokens
        await prisma.user.update({
            where: { id: user.id },
            data: {
                isVerified: true,
                verifyCode: null,
                verifyCodeExpires: null,
            },
        });

        return NextResponse.json({ message: "E-postanız başarıyla doğrulandı.", id: user.id }, { status: 200 });
    } catch (err) {
        console.error("Verify email error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
