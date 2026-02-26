/**
 * Slug'a sahip kategoriyi DB'de arar.
 * Bulamazsa categoryTree'den tüm üst zinciri upsert eder.
 * İkisinde de bulunamazsa null döner (geçersiz slug).
 */
import { prisma } from "@/lib/prisma";
import { categoryTree, CategoryNode, findPath } from "@/lib/categories";

async function upsertChain(path: CategoryNode[]): Promise<void> {
    let parentId: string | undefined;
    for (const node of path) {
        const record = await prisma.category.upsert({
            where: { slug: node.slug },
            update: { name: node.name, icon: node.icon ?? null, parentId: parentId ?? null },
            create: { name: node.name, slug: node.slug, icon: node.icon ?? null, parentId: parentId ?? null },
        });
        parentId = record.id;
    }
}

export async function ensureCategory(slug: string) {
    // 1. Önce DB'den bak
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (existing) return existing;

    // 2. categoryTree içinde yol bul ve upsert et
    const path = findPath(slug, categoryTree);
    if (!path) return null; // Geçersiz slug

    await upsertChain(path);
    return await prisma.category.findUnique({ where: { slug } });
}
