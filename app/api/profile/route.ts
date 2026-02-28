import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import bcrypt from "bcryptjs";
import { getMobileUser } from "@/lib/mobile-auth";
import { sendProfileUpdateVerificationEmail } from "@/lib/mail";

export async function GET(request: Request) {
    try {
        const userSession = await getMobileUser(request);
        if (!userSession?.id) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        const user = await prisma.user.findUnique({
            where: { id: userSession.id },
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
        const userSession = await getMobileUser(request);
        if (!userSession?.id) {
            return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
        }

        const body = await request.json();
        const { name, email, phone, password, passwordConfirm, currentPassword, verificationCode } = body;

        if (!name || !email) {
            return NextResponse.json({ message: "Ad ve E-posta alanları zorunludur" }, { status: 400 });
        }

        if (password) {
            if (!currentPassword) {
                return NextResponse.json({ message: "Şifre değişikliği için mevcut şifrenizi girmelisiniz" }, { status: 400 });
            }

            const dbUser = await prisma.user.findUnique({
                where: { id: userSession.id },
                select: { password: true }
            });

            if (!dbUser || !dbUser.password) {
                return NextResponse.json({ message: "Kullanıcı kaydı hatalı" }, { status: 404 });
            }

            const isPasswordValid = await bcrypt.compare(currentPassword, dbUser.password);
            if (!isPasswordValid) {
                return NextResponse.json({ message: "Mevcut şifreniz hatalı" }, { status: 400 });
            }

            if (password !== passwordConfirm) {
                return NextResponse.json({ message: "Şifreler birbiriyle eşleşmiyor" }, { status: 400 });
            }
        }

        // 1. If verificationCode is missing, send a new code
        if (!verificationCode) {
            const code = Math.floor(100000 + Math.random() * 900000).toString();
            const expires = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

            await prisma.user.update({
                where: { id: userSession.id },
                data: {
                    verifyCode: code,
                    verifyCodeExpires: expires
                }
            });

            await sendProfileUpdateVerificationEmail(userSession.email, code);

            return NextResponse.json({
                message: "Lütfen e-posta adresinize gönderilen 6 haneli doğrulama kodunu girin.",
                requiresVerification: true
            }, { status: 202 });
        }

        // 2. If verificationCode is present, verify it
        const user = await prisma.user.findUnique({
            where: { id: userSession.id },
            select: { verifyCode: true, verifyCodeExpires: true }
        });

        if (!user || user.verifyCode !== verificationCode || !user.verifyCodeExpires || user.verifyCodeExpires < new Date()) {
            return NextResponse.json({ message: "Geçersiz veya süresi dolmuş doğrulama kodu" }, { status: 400 });
        }

        // Email uniqueness check if email was changed
        if (email !== userSession.email) {
            const existing = await prisma.user.findUnique({ where: { email } });
            if (existing) {
                return NextResponse.json({ message: "Bu e-posta adresi zaten kullanılıyor" }, { status: 400 });
            }
        }

        const updateData: any = { name, email, phone: phone || null };

        if (password) {
            updateData.password = await bcrypt.hash(password, 10);
        }

        // Clear verification code after success
        updateData.verifyCode = null;
        updateData.verifyCodeExpires = null;

        const updatedUser = await prisma.user.update({
            where: { id: userSession.id },
            data: updateData
        });

        return NextResponse.json({
            message: "Profil başarıyla güncellendi",
            user: {
                id: updatedUser.id,
                name: updatedUser.name,
                email: updatedUser.email,
                phone: updatedUser.phone,
                avatar: updatedUser.avatar
            }
        });

    } catch (error) {
        console.error("Update Profile Error:", error);
        return NextResponse.json({ message: "Bir hata oluştu" }, { status: 500 });
    }
}
