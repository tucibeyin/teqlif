// Teqlif — Recursive 4-Katmanlı Kategori Ağacı
// Yapı: Gayrimenkul → Konut → Satılık → Daire
// Leaf tespiti: node.children.length === 0
// API'ye sadece leaf slug'ı gönderilir.

export type CategoryNode = {
    slug: string;
    name: string;
    icon?: string;
    children: CategoryNode[];
};

// ─── Yardımcı fonksiyonlar ─────────────────────────────────────────────────

/** Tüm ağaçta slug ile node bulur */
export function findNode(
    slug: string,
    nodes: CategoryNode[] = categoryTree,
): CategoryNode | null {
    for (const node of nodes) {
        if (node.slug === slug) return node;
        const found = findNode(slug, node.children);
        if (found) return found;
    }
    return null;
}

/** Kökten yaprağa giden yolu döndürür */
export function findPath(
    slug: string,
    nodes: CategoryNode[] = categoryTree,
    path: CategoryNode[] = [],
): CategoryNode[] | null {
    for (const node of nodes) {
        const next = [...path, node];
        if (node.slug === slug) return next;
        const found = findPath(slug, node.children, next);
        if (found) return found;
    }
    return null;
}

/** Çocuğu olmayan node'dur (yaprak) */
export function isLeaf(node: CategoryNode): boolean {
    return node.children.length === 0;
}

// ─── Slug yardımcısı ───────────────────────────────────────────────────────
function s(base: string, name: string): string {
    const suffix = name
        .toLowerCase()
        .replace(/[^a-z0-9ğüşıöç]/gi, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "");
    return `${base}-${suffix}`;
}

function leaves(parent: string, names: string[]): CategoryNode[] {
    return names.map((n) => ({ slug: s(parent, n), name: n, children: [] }));
}

// ─── Ağaç Verisi ───────────────────────────────────────────────────────────

const GR = "gayrimenkul";
const KNT = s(GR, "konut");
const ISY = s(GR, "is-yeri");
const ARS = s(GR, "arsa");
const BIN = s(GR, "bina");
const DVM = s(GR, "devre-mulk");
const TRT = s(GR, "turistik-tesis");

export const categoryTree: CategoryNode[] = [
    // ── GAYRİMENKUL ─────────────────────────────────────────────────────────
    {
        slug: GR,
        name: "Gayrimenkul",
        icon: "🏠",
        children: [
            // KONUT
            {
                slug: KNT, name: "Konut", icon: "🏠",
                children: [
                    { slug: s(KNT, "satilik"), name: "Satılık", children: leaves(s(KNT, "satilik"), ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Çiftlik Evi", "Köşk & Konak", "Yalı", "Yalı Dairesi", "Yazlık", "Kooperatif"]) },
                    { slug: s(KNT, "kiralik"), name: "Kiralık", children: leaves(s(KNT, "kiralik"), ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Çiftlik Evi", "Köşk & Konak", "Yalı", "Yalı Dairesi", "Yazlık", "Kooperatif"]) },
                    { slug: s(KNT, "turistik-gunluk-kiralik"), name: "Turistik Günlük Kiralık", children: leaves(s(KNT, "turistik-gunluk-kiralik"), ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Yazlık", "Apart Otel", "Pansiyon"]) },
                    { slug: s(KNT, "devren-satilik"), name: "Devren Satılık", children: leaves(s(KNT, "devren-satilik"), ["Daire", "Rezidans", "Müstakil Ev", "Villa"]) },
                ],
            },
            // İŞ YERİ
            {
                slug: ISY, name: "İş Yeri", icon: "🏢",
                children: [
                    { slug: s(ISY, "satilik"), name: "Satılık", children: leaves(s(ISY, "satilik"), ["Akaryakıt İstasyonu", "Apartman Dairesi", "Atölye", "AVM", "Büfe", "Büro & Ofis", "Çiftlik", "Depo & Antrepo", "Düğün Salonu", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "Garaj & Park Yeri", "İmalathane", "İş Hanı Katı & Ofisi", "Kafe & Bar", "Kantin", "Kıraathane", "Komple Bina", "Otopark & Garaj", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Pazar Yeri", "Plaza", "Plaza Katı & Ofisi", "Restoran & Lokanta", "Rezidans Katı & Ofisi", "Sağlık Merkezi", "SPA, Hamam & Sauna", "Spor Tesisi", "Villa", "Yurt"]) },
                    { slug: s(ISY, "kiralik"), name: "Kiralık", children: leaves(s(ISY, "kiralik"), ["Akaryakıt İstasyonu", "Apartman Dairesi", "Atölye", "AVM", "Büfe", "Büro & Ofis", "Çiftlik", "Depo & Antrepo", "Düğün Salonu", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "Garaj & Park Yeri", "İmalathane", "İş Hanı Katı & Ofisi", "Kafe & Bar", "Kantin", "Kıraathane", "Komple Bina", "Otopark & Garaj", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Pazar Yeri", "Plaza", "Plaza Katı & Ofisi", "Restoran & Lokanta", "Rezidans Katı & Ofisi", "Sağlık Merkezi", "SPA, Hamam & Sauna", "Spor Tesisi", "Villa", "Yurt"]) },
                    { slug: s(ISY, "devren-satilik"), name: "Devren Satılık", children: leaves(s(ISY, "devren-satilik"), ["Atölye", "Büfe", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "İmalathane", "Kafe & Bar", "Kıraathane", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Restoran & Lokanta", "SPA, Hamam & Sauna", "Spor Tesisi"]) },
                    { slug: s(ISY, "devren-kiralik"), name: "Devren Kiralık", children: leaves(s(ISY, "devren-kiralik"), ["Atölye", "Büfe", "Dükkan & Mağaza", "İmalathane", "Kafe & Bar", "Kıraathane", "Restoran & Lokanta"]) },
                ],
            },
            // ARSA
            {
                slug: ARS, name: "Arsa", icon: "🌿",
                children: [
                    { slug: s(ARS, "satilik"), name: "Satılık", children: [] },
                    { slug: s(ARS, "kiralik"), name: "Kiralık", children: [] },
                    { slug: s(ARS, "kat-karsiligi"), name: "Kat Karşılığı", children: [] },
                ],
            },
            // BİNA
            {
                slug: BIN, name: "Bina", icon: "🏗️",
                children: [
                    { slug: s(BIN, "satilik"), name: "Satılık", children: [] },
                    { slug: s(BIN, "kiralik"), name: "Kiralık", children: [] },
                ],
            },
            // DEVRE MÜLK
            {
                slug: DVM, name: "Devre Mülk", icon: "🏖️",
                children: [
                    { slug: s(DVM, "satilik"), name: "Satılık", children: [] },
                    { slug: s(DVM, "kiralik"), name: "Kiralık", children: [] },
                ],
            },
            // TURİSTİK TESİS
            {
                slug: TRT, name: "Turistik Tesis", icon: "🏨",
                children: [
                    { slug: s(TRT, "satilik"), name: "Satılık", children: leaves(s(TRT, "satilik"), ["Otel", "Apart Otel", "Butik Otel", "Motel", "Pansiyon", "Tatil Köyü"]) },
                    { slug: s(TRT, "kiralik"), name: "Kiralık", children: leaves(s(TRT, "kiralik"), ["Otel", "Apart Otel", "Butik Otel", "Motel", "Pansiyon", "Tatil Köyü"]) },
                ],
            },
        ],
    },

    // ── DİĞER KATEGORİLER (leaf = kendisi) ───────────────────────────────────
    { slug: "elektronik", name: "Elektronik", icon: "💻", children: [] },
    { slug: "arac", name: "Araç", icon: "🚗", children: [] },
    { slug: "giyim", name: "Giyim & Moda", icon: "👗", children: [] },
    { slug: "mobilya", name: "Mobilya & Ev", icon: "🛋️", children: [] },
    { slug: "spor", name: "Spor & Outdoor", icon: "⚽", children: [] },
    { slug: "kitap", name: "Kitap & Hobi", icon: "📚", children: [] },
    { slug: "koleksiyon", name: "Koleksiyon & Antika", icon: "🏺", children: [] },
    { slug: "cocuk", name: "Bebek & Çocuk", icon: "🧸", children: [] },
    { slug: "bahce", name: "Bahçe & Tarım", icon: "🌱", children: [] },
    { slug: "hayvan", name: "Hayvanlar", icon: "🐾", children: [] },
    { slug: "diger", name: "Diğer", icon: "📦", children: [] },
];

// Geriye dönük uyumluluk için (import edip kullanan eski yerler)
export const categories = categoryTree.map((c) => ({
    slug: c.slug, name: c.name, icon: c.icon,
}));
