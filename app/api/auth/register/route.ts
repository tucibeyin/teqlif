import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";

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
            return NextResponse.json({ error: "Bu email zaten kayıtlı." }, { status: 409 });
        }

        const hashed = await bcrypt.hash(password, 12);
        const user = await prisma.user.create({
            data: { name, email, phone: phone || null, password: hashed },
        });

        return NextResponse.json({ id: user.id, name: user.name, email: user.email }, { status: 201 });
    } catch (err) {
        console.error("Register error:", err);
        return NextResponse.json({ error: "Sunucu hatası." }, { status: 500 });
    }
}
