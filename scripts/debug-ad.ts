import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
    const adId = "cmm4i7n5o000wcgx4pp2656zb";
    console.log(`Checking ad ${adId}...`);

    const ad = await prisma.ad.findUnique({
        where: { id: adId },
        include: {
            bids: {
                orderBy: { amount: "desc" }
            }
        }
    });

    if (!ad) {
        console.log("Ad not found");
        return;
    }

    console.log("Ad Status:", ad.status);
    console.log("Bids Count:", ad.bids.length);

    ad.bids.forEach(bid => {
        console.log(`- Bid ID: ${bid.id}, Amount: ${bid.amount}, Status: ${bid.status}`);
    });

    const acceptedBids = ad.bids.filter(b => b.status === 'ACCEPTED');
    console.log("Accepted Bids Count:", acceptedBids.length);

    if (ad.status === 'SOLD' && acceptedBids.length === 0) {
        console.log("CRITICAL: Ad is SOLD but has 0 accepted bids. This is the bug.");

        console.log("Fixing ad status to ACTIVE...");
        const fixedAd = await prisma.ad.update({
            where: { id: adId },
            data: { status: 'ACTIVE' }
        });
        console.log("Ad status fixed to:", fixedAd.status);
    }
}

main()
    .catch(console.error)
    .finally(() => prisma.$disconnect());
