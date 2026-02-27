import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
    console.log("🧹 Veritabanındaki tüm ilanlar siliniyor...");

    try {
        // Ad tablosundaki her şeyi siler. 
        // İlişkili Bid ve Favorite kayıtları 'onDelete: Cascade' sayesinde otomatik silinir.
        // Conversation kayıtlarındaki 'adId' ise 'SetNull' olur.
        const deleted = await prisma.ad.deleteMany();

        console.log(`✅ İşlem başarılı. Toplam ${deleted.count} ilan silindi.`);
    } catch (error) {
        console.error("❌ Hata oluştu:", error);
    } finally {
        await prisma.$disconnect();
    }
}

main();
