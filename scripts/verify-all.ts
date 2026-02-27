import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const result = await prisma.user.updateMany({
        data: { isVerified: true }
    });
    console.log(`Updated ${result.count} users to isVerified: true`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
