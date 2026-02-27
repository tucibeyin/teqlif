import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const count = await prisma.user.count();
    console.log(`Total users: ${count}`);

    const sample = await prisma.user.findMany({
        take: 3,
        select: { id: true, name: true, email: true, fcmToken: true }
    });
    console.log('Sample users:', JSON.stringify(sample, null, 2));
}

main().catch(console.error).finally(() => prisma.$disconnect());
