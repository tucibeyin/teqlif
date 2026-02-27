import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const FALLBACK_SECRET = "fallback-secret-change-me";
const AUTH_SECRET = process.env.AUTH_SECRET || FALLBACK_SECRET;
const NEXTAUTH_SECRET = process.env.NEXTAUTH_SECRET;

console.log("AUTH_SECRET (used in API):", AUTH_SECRET);
console.log("NEXTAUTH_SECRET (in .env):", NEXTAUTH_SECRET);

const payload = { id: 'test-id' };
const token = jwt.sign(payload, FALLBACK_SECRET);

try {
    jwt.verify(token, FALLBACK_SECRET);
    console.log("Verified with FALLBACK_SECRET: YES");
} catch (e) { console.log("Verified with FALLBACK_SECRET: NO"); }

if (NEXTAUTH_SECRET) {
    try {
        jwt.verify(token, NEXTAUTH_SECRET);
        console.log("Verified with NEXTAUTH_SECRET: YES");
    } catch (e) { console.log("Verified with NEXTAUTH_SECRET: NO"); }
}
