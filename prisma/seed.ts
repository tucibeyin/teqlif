import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";
import { provinces, allDistricts } from "../lib/locations";
import { categoryTree, CategoryNode } from "../lib/categories";

const prisma = new PrismaClient();

/** DFS ile kategoriler upsert edilir — önce parent kaydedilmeli */
async function seedCategory(node: CategoryNode, parentId?: string) {
    await prisma.category.upsert({
        where: { slug: node.slug },
        update: { name: node.name, icon: node.icon ?? null, parentId: parentId ?? null },
        create: { name: node.name, slug: node.slug, icon: node.icon ?? null, parentId: parentId ?? null },
    });
    const record = await prisma.category.findUnique({ where: { slug: node.slug } });
    for (const child of node.children) {
        await seedCategory(child, record!.id);
    }
}

async function main() {
    console.log("🌱 Veritabanı tohum ekiliyor...");

    // Kategoriler
    for (const root of categoryTree) {
        await seedCategory(root);
    }
    console.log("✅ Kategoriler eklendi");

    // İller
    for (const prov of provinces) {
        await prisma.province.upsert({
            where: { id: prov.id },
            update: {},
            create: { id: prov.id, name: prov.name },
        });
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
    .catch((e) => { console.error(e); process.exit(1); })
    .finally(async () => { await prisma.$disconnect(); });
