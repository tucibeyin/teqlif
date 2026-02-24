import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";

export async function POST(req: NextRequest) {
    try {
        const { email, code, newPassword } = await req.json();

        if (!email || !code || !newPassword) {
            return NextResponse.json({ error: "E-posta, kod ve yeni şifre zorunludur." }, { status: 400 });
        }

        if (newPassword.length < 6) {
            return NextResponse.json({ error: "Yeni şifre en az 6 karakter olmalıdır." }, { status: 400 });
        }

        const user = await prisma.user.findUnique({ where: { email } });

        if (!user) {
            return NextResponse.json({ error: "Kullanıcı bulunamadı." }, { status: 404 });
        }

        if (user.resetCode !== code) {
            return NextResponse.json({ error: "Geçersiz sıfırlama kodu." }, { status: 400 });
        }

        if (user.resetCodeExpires && new Date(user.resetCodeExpires) < new Date()) {
            return NextResponse.json({ error: "Sıfırlama kodunun süresi dolmuş." }, { status: 400 });
        }

        const hashed = await bcrypt.hash(newPassword, 12);

        await prisma.user.update({
            where: { id: user.id },
            data: {
                password: hashed,
                resetCode: null,
                resetCodeExpires: null,
            },
        });

        return NextResponse.json({ message: "Şifreniz başarıyla sıfırlandı." }, { status: 200 });
    } catch (err) {
        console.error("Reset password error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
