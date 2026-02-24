import { NextRequest, NextResponse } from "next/server";
import { writeFile, mkdir } from "fs/promises";
import { join } from "path";
import { existsSync } from "fs";
import { getMobileUser } from "@/lib/mobile-auth";

export const maxDuration = 60;

export async function POST(req: NextRequest) {
    try {
        const currentUser = await getMobileUser(req);
        if (!currentUser?.id) {
            return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
        }

        const data = await req.formData();
        const file: File | null = data.get("file") as unknown as File;

        if (!file) {
            return NextResponse.json({ error: "Dosya bulunamadı" }, { status: 400 });
        }

        const bytes = await file.arrayBuffer();
        const buffer = Buffer.from(bytes);

        // Save everything to public/uploads directly.
        // If a cloud provider is used later, they should be uploaded to S3/Cloudinary instead.
        const baseUploadPath = join(process.cwd(), "public");
        const uploadsDir = join(baseUploadPath, "uploads");

        if (!existsSync(uploadsDir)) {
            await mkdir(uploadsDir, { recursive: true });
        }

        const uniqueSuffix = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
        const ext = file.name.split(".").pop();
        const filename = `${uniqueSuffix}.${ext}`;
        const filePath = join(uploadsDir, filename);

        await writeFile(filePath, buffer);

        // Next.js serves the 'public' folder directly at the root.
        return NextResponse.json({ url: `/uploads/${filename}` });
    } catch (error) {
        console.error("Upload error:", error);
        return NextResponse.json({ error: "Dosya yükleme başarısız" }, { status: 500 });
    }
}
