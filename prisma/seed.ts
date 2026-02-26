import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";
import { provinces, allDistricts } from "../lib/locations";
import { categoryTree } from "../lib/categories";

const prisma = new PrismaClient();

async function main() {
    console.log("🌱 Veritabanı tohum ekiliyor...");

    // ── Kategoriler (3 Seviyeli) ────────────────────────────────────────
    for (const root of categoryTree) {
        // Level-1: Ana Kategori (root)
        await prisma.category.upsert({
            where: { slug: root.slug },
            update: { name: root.name, icon: root.icon },
            create: { name: root.name, slug: root.slug, icon: root.icon },
        });

        for (const sub of root.children) {
            // Level-2: Alt Kategori (Satılık, Kiralık…)
            const parentRecord = await prisma.category.findUnique({ where: { slug: root.slug } });
            await prisma.category.upsert({
                where: { slug: sub.slug },
                update: { name: sub.name, parentId: parentRecord!.id },
                create: { name: sub.name, slug: sub.slug, parentId: parentRecord!.id },
            });

            for (const leaf of sub.leaves) {
                // Level-3: İlan Türü (Daire, Villa…)
                const subRecord = await prisma.category.findUnique({ where: { slug: sub.slug } });
                await prisma.category.upsert({
                    where: { slug: leaf.slug },
                    update: { name: leaf.name, parentId: subRecord!.id },
                    create: { name: leaf.name, slug: leaf.slug, parentId: subRecord!.id },
                });
            }
        }
    }
    console.log("✅ Kategoriler eklendi");

    // ── İller ──────────────────────────────────────────────────────────
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

    // ── Demo kullanıcı ─────────────────────────────────────────────────
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
