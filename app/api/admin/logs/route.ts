import { NextRequest, NextResponse } from "next/server";
import { logger } from "@/lib/logger";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
    // Note: In a real app, this should be protected by admin auth
    return NextResponse.json(logger.getLogs());
}

export async function DELETE(req: NextRequest) {
    logger.clear();
    return NextResponse.json({ message: "Logs cleared" });
}
