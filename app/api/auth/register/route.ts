import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";
import { sendVerificationEmail } from "@/lib/mail";

export async function POST(req: NextRequest) {
    try {
        const { name, email, phone, password } = await req.json();

        if (!name || !email || !password) {
            return NextResponse.json({ error: "Ad, email ve şifre zorunludur." }, { status: 400 });
        }

        if (password.length < 6) {
            return NextResponse.json({ error: "Şifre en az 6 karakter olmalıdır." }, { status: 400 });
        }

        const existing = await prisma.user.findUnique({ where: { email } });
        if (existing) {
            if (existing.isVerified) {
                return NextResponse.json({ error: "Bu email zaten kayıtlı." }, { status: 409 });
            } else {
                // User exists but is not verified. Resend OTP and update password/name.
                const hashed = await bcrypt.hash(password, 12);
                const verifyCode = Math.floor(100000 + Math.random() * 900000).toString();
                const verifyCodeExpires = new Date(Date.now() + 15 * 60 * 1000);

                const updatedUser = await prisma.user.update({
                    where: { email },
                    data: {
                        name,
                        phone: phone || null,
                        password: hashed,
                        verifyCode,
                        verifyCodeExpires,
                    },
                });

                await sendVerificationEmail(updatedUser.email, verifyCode);

                return NextResponse.json({
                    id: updatedUser.id,
                    name: updatedUser.name,
                    email: updatedUser.email,
                    pendingVerification: true
                }, { status: 200 });
            }
        }

        const hashed = await bcrypt.hash(password, 12);

        // Generate a 6-digit verification code
        const verifyCode = Math.floor(100000 + Math.random() * 900000).toString();
        // Set expiration time to 15 minutes from now
        const verifyCodeExpires = new Date(Date.now() + 15 * 60 * 1000);

        const user = await prisma.user.create({
            data: {
                name,
                email,
                phone: phone || null,
                password: hashed,
                verifyCode,
                verifyCodeExpires,
                isVerified: false
            },
        });

        await sendVerificationEmail(user.email, verifyCode);

        return NextResponse.json({
            id: user.id,
            name: user.name,
            email: user.email,
            pendingVerification: true
        }, { status: 201 });
    } catch (err: any) {
        console.error("Register error:", err);
        return NextResponse.json({ error: "Sunucu hatası: " + (err?.message || "Bilinmiyor") }, { status: 500 });
    }
}
