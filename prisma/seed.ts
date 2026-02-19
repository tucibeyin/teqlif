import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";
import { provinces, allDistricts } from "../lib/locations";
import { categories } from "../lib/categories";

const prisma = new PrismaClient();

async function main() {
    console.log("🌱 Veritabanı tohum ekiliyor...");

    // Kategoriler
    for (const cat of categories) {
        await prisma.category.upsert({
            where: { slug: cat.slug },
            update: {},
            create: { name: cat.name, slug: cat.slug, icon: cat.icon },
        });
    }
    console.log("✅ Kategoriler eklendi");

    // İller
    for (const prov of provinces) {
        await prisma.province.upsert({
            where: { id: prov.id },
            update: {},
            create: { id: prov.id, name: prov.name },
        });
        // İlçeler
        const distList = allDistricts[prov.id] ?? [];
        for (const dist of distList) {
            await prisma.district.upsert({
                where: { id: dist.id },
                update: {},
                create: { id: dist.id, name: dist.name, provinceId: prov.id },
            });
        }
    }
    console.log("✅ İller ve ilçeler eklendi");

    // Demo kullanıcı
    const hashedPassword = await bcrypt.hash("teqlif123", 12);
    const demoUser = await prisma.user.upsert({
        where: { email: "demo@teqlif.com" },
        update: {},
        create: {
            name: "Demo Kullanıcı",
            email: "demo@teqlif.com",
            password: hashedPassword,
            phone: "05301234567",
        },
    });
    console.log("✅ Demo kullanıcı oluşturuldu:", demoUser.email);

    console.log("🎉 Seed tamamlandı!");
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
