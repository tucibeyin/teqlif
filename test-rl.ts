import { actionRatelimiter } from "./lib/rate-limit";

async function run() {
    try {
        const res = await actionRatelimiter.limit("127.0.0.1");
        console.log("Success:", res);
        process.exit(0);
    } catch (e) {
        console.error("Error:", e);
        process.exit(1);
    }
}
run();
