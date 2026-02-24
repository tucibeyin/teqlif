import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function run() {
    const users = await prisma.user.findMany({ select: { id: true, email: true, name: true, fcmToken: true } });
    console.log("Tokens in DB:");
    console.table(users);
}
run();
