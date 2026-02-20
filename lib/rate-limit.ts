import { Ratelimit } from "@upstash/ratelimit";
import { redis } from "./redis";

// Define an adapter or simply cast to any to bypass type mismatch since Upstash Ratelimit expects its own Redis interface
const ratelimitRedis = {
    sadd: (key: string, ...members: string[]) => redis.sadd(key, ...members),
    eval: (script: string, keys: string[], args: unknown[]) =>
        redis.eval(script, keys.length, ...keys, ...(args.map(a => String(a)))),
    // Use any as a fallback to avoid strict Type issues on adapter
} as any;

// Create a new ratelimiter, that allows 10 requests per 10 seconds
export const apiRatelimiter = new Ratelimit({
    redis: ratelimitRedis,
    limiter: Ratelimit.slidingWindow(10, "10 s"),
    analytics: false,
    prefix: "@upstash/ratelimit",
});

// Stricter rate limit for actions like posting ads or bids: 5 requests per 1 minute
export const actionRatelimiter = new Ratelimit({
    redis: ratelimitRedis,
    limiter: Ratelimit.slidingWindow(5, "1 m"),
    analytics: false,
    prefix: "@upstash/ratelimit",
});
