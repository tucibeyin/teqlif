import { auth } from "@/auth";
import jwt from "jsonwebtoken";
import { prisma } from "@/lib/prisma";

const JWT_SECRET = process.env.NEXTAUTH_SECRET || process.env.AUTH_SECRET;
if (!JWT_SECRET) {
    console.error("FATAL: NEXTAUTH_SECRET or AUTH_SECRET is not defined. Mobile auth will fail.");
}

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
    const authHeader = req.headers.get("authorization");
    console.log(`[getMobileUser] Auth Header: ${authHeader ? "Present" : "Missing"}`);

    // 1. Try mobile JWT first to avoid next-auth concurrency blocking on parallel mobile api requests
    if (authHeader?.startsWith("Bearer ") && JWT_SECRET) {
        try {
            const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as any;
            console.log(`[getMobileUser] JWT Verified for: ${payload?.id}`);
            if (payload?.id) return payload as MobileUser;
        } catch (e) {
            console.warn(`[getMobileUser] JWT verification failed: ${e instanceof Error ? e.message : String(e)}`);
        }
    }

    // 2. Fallback to next-auth session for browser users
    const session = await auth();
    console.log(`[getMobileUser] Fallback to session: ${!!session?.user?.id}`);

    if (session?.user?.id) {
        const user = await prisma.user.findUnique({
            where: { id: session.user.id },
            select: { id: true, email: true, name: true },
        });
        if (user) return user;
    }

    return null;
}
