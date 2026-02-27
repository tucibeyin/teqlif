import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const users = await prisma.user.findMany({
        where: { fcmToken: { not: null } },
        select: { id: true, name: true, email: true, fcmToken: true },
        orderBy: { updatedAt: 'desc' },
        take: 5
    });
    console.log(JSON.stringify(users, null, 2));
}

main().catch(console.error).finally(() => prisma.$disconnect());
