import { NextResponse } from 'next/server';

export async function GET() {
    return NextResponse.json({
        serverTime: Date.now()
    }, {
        headers: {
            // Prevent caching for accurate timing
            'Cache-Control': 'no-store, max-age=0, must-revalidate',
        }
    });
}
