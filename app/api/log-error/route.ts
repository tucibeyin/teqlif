import { NextRequest, NextResponse } from 'next/server';
import logger from '@/lib/logger';

export async function POST(req: NextRequest) {
    try {
        const body = await req.json();

        const {
            page = 'unknown',
            message = 'Unknown error',
            stack,
            userAgent,
            userId,
        } = body;

        // Validate — don't log empty or spammy requests
        if (!message || message.length < 3) {
            return NextResponse.json({ ok: true });
        }

        logger.frontendError({
            page,
            message: String(message).substring(0, 500),
            stack: stack ? String(stack).substring(0, 800) : undefined,
            userAgent: userAgent || req.headers.get('user-agent') || 'unknown',
            userId,
        });

        return NextResponse.json({ ok: true });
    } catch (e) {
        // Don't fail loudly — this is a fire-and-forget endpoint
        return NextResponse.json({ ok: true });
    }
}
