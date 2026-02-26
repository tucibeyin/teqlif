/**
 * Verilen slug'a sahip kategoriyi DB'de arar.
 * Bulamazsa, lib/categories.ts'teki categoryTree'den hiyerarşiyi oluşturur
 * ve upsert eder. Geçersiz bir slug ise null döner.
 */
import { prisma } from "@/lib/prisma";
import { categoryTree } from "@/lib/categories";

export async function ensureCategory(slug: string) {
    // 1. Önce doğrudan DB'den bak
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (existing) return existing;

    // 2. categoryTree içinde ara ve hiyerarşiyi oluştur
    for (const root of categoryTree) {
        // Root slug
        if (root.slug === slug) {
            return await prisma.category.upsert({
                where: { slug },
                update: { name: root.name, icon: root.icon },
                create: { name: root.name, slug, icon: root.icon },
            });
        }

        for (const sub of root.children) {
            // Sub slug
            if (sub.slug === slug) {
                const rootCat = await prisma.category.upsert({
                    where: { slug: root.slug },
                    update: { name: root.name, icon: root.icon },
                    create: { name: root.name, slug: root.slug, icon: root.icon },
                });
                return await prisma.category.upsert({
                    where: { slug },
                    update: { name: sub.name, parentId: rootCat.id },
                    create: { name: sub.name, slug, parentId: rootCat.id },
                });
            }

            // Leaf slug
            for (const leaf of sub.leaves) {
                if (leaf.slug === slug) {
                    const rootCat = await prisma.category.upsert({
                        where: { slug: root.slug },
                        update: { name: root.name, icon: root.icon },
                        create: { name: root.name, slug: root.slug, icon: root.icon },
                    });
                    const subCat = await prisma.category.upsert({
                        where: { slug: sub.slug },
                        update: { name: sub.name, parentId: rootCat.id },
                        create: { name: sub.name, slug: sub.slug, parentId: rootCat.id },
                    });
                    return await prisma.category.upsert({
                        where: { slug },
                        update: { name: leaf.name, parentId: subCat.id },
                        create: { name: leaf.name, slug, parentId: subCat.id },
                    });
                }
            }
        }
    }

    // Slug categoryTree'de de bulunamadı → geçersiz
    return null;
}
