import { NextRequest, NextResponse } from "next/server";
import { join } from "path";
import { existsSync } from "fs";
import { readFile } from "fs/promises";

export async function GET(req: NextRequest, { params }: { params: Promise<{ filename: string }> }) {
    try {
        const { filename } = await params;

        if (!filename) {
            return new NextResponse("Not Found", { status: 404 });
        }

        const baseUploadPath = join(process.cwd(), "public");
        const uploadsDir = join(baseUploadPath, "uploads");
        const filePath = join(uploadsDir, filename);

        // Security check to ensure the file path is within the uploads directory
        if (!filePath.startsWith(uploadsDir)) {
            return new NextResponse("Forbidden", { status: 403 });
        }

        if (!existsSync(filePath)) {
            return new NextResponse("Image Not Found", { status: 404 });
        }

        const buffer = await readFile(filePath);

        let contentType = "image/jpeg";
        const ext = filename.split('.').pop()?.toLowerCase();
        if (ext === "png") contentType = "image/png";
        else if (ext === "gif") contentType = "image/gif";
        else if (ext === "webp") contentType = "image/webp";
        else if (ext === "svg") contentType = "image/svg+xml";

        return new NextResponse(buffer, {
            headers: {
                "Content-Type": contentType,
                "Cache-Control": "public, max-age=31536000, immutable",
            },
        });
    } catch (error) {
        console.error("Error serving uploaded image:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
