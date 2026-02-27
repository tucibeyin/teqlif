import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
    console.log("Listing all ads...");
    const ads = await prisma.ad.findMany({
        take: 10,
        orderBy: { createdAt: 'desc' },
        include: { _count: { select: { bids: true } } }
    });

    console.log(`Found ${ads.length} ads:`);
    ads.forEach(ad => {
        console.log(`- ID: ${ad.id}, Status: ${ad.status}, Bids: ${ad._count.bids}, Title: ${ad.title}`);
    });
}

main()
    .catch(console.error)
    .finally(() => prisma.$disconnect());
