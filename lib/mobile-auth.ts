import { auth } from "@/auth";
import jwt from "jsonwebtoken";
import { prisma } from "@/lib/prisma";

const JWT_SECRET = process.env.NEXTAUTH_SECRET || process.env.AUTH_SECRET || "fallback-secret-change-me";

interface MobileUser {
    id: string;
    email: string;
    name: string;
}

/**
 * Returns the authenticated user from either:
 *  - a next-auth web session (cookie-based), or
 *  - a mobile JWT Bearer token in the Authorization header
 *
 * Returns null if neither is present / valid.
 */
export async function getMobileUser(req: Request): Promise<MobileUser | null> {
    // 1. Try mobile JWT first to avoid next-auth concurrency blocking on parallel mobile api requests
    const authHeader = req.headers.get("authorization");
    if (authHeader?.startsWith("Bearer ")) {
        try {
            const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as MobileUser;
            if (payload?.id) return payload;
        } catch (e) {
            // Do not return null here, fall back to NextAuth session checking
            console.warn("JWT verification failed, falling back to NextAuth", e);
        }
    }

    // 2. Fallback to next-auth session for browser users
    const session = await auth();
    if (session?.user?.id) {
        const user = await prisma.user.findUnique({
            where: { id: session.user.id },
            select: { id: true, email: true, name: true },
        });
        if (user) return user;
    }

    return null;
}
