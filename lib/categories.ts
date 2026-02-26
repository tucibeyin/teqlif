// Teqlif — 3 Seviyeli Kategori Ağacı
// Ana Kategori > Alt Kategori (Satılık/Kiralık…) > İlan Türü (leaf)
// Sadece leaf node'ların slug'ı API'ye gönderilir.

export type LeafCategory = {
    slug: string;
    name: string;
};

export type SubCategory = {
    slug: string;
    name: string;
    leaves: LeafCategory[];
};

export type RootCategory = {
    slug: string;
    name: string;
    icon: string;
    children: SubCategory[];
};

function makeLeaves(parentSlug: string, names: string[]): LeafCategory[] {
    return names.map((n) => ({
        slug: `${parentSlug}-${n.toLowerCase().replace(/[^a-z0-9ğüşıöçA-ZÜŞĞÖÇI]/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")}`,
        name: n,
    }));
}

export const categoryTree: RootCategory[] = [
    {
        slug: "konut",
        name: "Konut",
        icon: "🏠",
        children: [
            {
                slug: "konut-satilik",
                name: "Satılık",
                leaves: makeLeaves("konut-satilik", ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Çiftlik Evi", "Köşk & Konak", "Yalı", "Yalı Dairesi", "Yazlık", "Kooperatif"]),
            },
            {
                slug: "konut-kiralik",
                name: "Kiralık",
                leaves: makeLeaves("konut-kiralik", ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Çiftlik Evi", "Köşk & Konak", "Yalı", "Yalı Dairesi", "Yazlık", "Kooperatif"]),
            },
            {
                slug: "konut-turistik-gunluk-kiralik",
                name: "Turistik Günlük Kiralık",
                leaves: makeLeaves("konut-turistik-gunluk-kiralik", ["Daire", "Rezidans", "Müstakil Ev", "Villa", "Yazlık", "Apart Otel", "Pansiyon"]),
            },
            {
                slug: "konut-devren-satilik",
                name: "Devren Satılık Konut",
                leaves: makeLeaves("konut-devren-satilik", ["Daire", "Rezidans", "Müstakil Ev", "Villa"]),
            },
        ],
    },
    {
        slug: "is-yeri",
        name: "İş Yeri",
        icon: "🏢",
        children: [
            {
                slug: "is-yeri-satilik",
                name: "Satılık",
                leaves: makeLeaves("is-yeri-satilik", ["Akaryakıt İstasyonu", "Apartman Dairesi", "Atölye", "AVM", "Büfe", "Büro & Ofis", "Çiftlik", "Depo & Antrepo", "Düğün Salonu", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "Garaj & Park Yeri", "İmalathane", "İş Hanı Katı & Ofisi", "Kafe & Bar", "Kantin", "Kıraathane", "Komple Bina", "Otopark & Garaj", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Pazar Yeri", "Plaza", "Plaza Katı & Ofisi", "Restoran & Lokanta", "Rezidans Katı & Ofisi", "Sağlık Merkezi", "SPA, Hamam & Sauna", "Spor Tesisi", "Villa", "Yurt"]),
            },
            {
                slug: "is-yeri-kiralik",
                name: "Kiralık",
                leaves: makeLeaves("is-yeri-kiralik", ["Akaryakıt İstasyonu", "Apartman Dairesi", "Atölye", "AVM", "Büfe", "Büro & Ofis", "Çiftlik", "Depo & Antrepo", "Düğün Salonu", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "Garaj & Park Yeri", "İmalathane", "İş Hanı Katı & Ofisi", "Kafe & Bar", "Kantin", "Kıraathane", "Komple Bina", "Otopark & Garaj", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Pazar Yeri", "Plaza", "Plaza Katı & Ofisi", "Restoran & Lokanta", "Rezidans Katı & Ofisi", "Sağlık Merkezi", "SPA, Hamam & Sauna", "Spor Tesisi", "Villa", "Yurt"]),
            },
            {
                slug: "is-yeri-devren-satilik",
                name: "Devren Satılık",
                leaves: makeLeaves("is-yeri-devren-satilik", ["Atölye", "Büfe", "Dükkan & Mağaza", "Fabrika & Üretim Tesisi", "İmalathane", "Kafe & Bar", "Kıraathane", "Oto Yıkama & Kuaför", "Pastane, Fırın & Tatlıcı", "Restoran & Lokanta", "SPA, Hamam & Sauna", "Spor Tesisi"]),
            },
            {
                slug: "is-yeri-devren-kiralik",
                name: "Devren Kiralık",
                leaves: makeLeaves("is-yeri-devren-kiralik", ["Atölye", "Büfe", "Dükkan & Mağaza", "İmalathane", "Kafe & Bar", "Kıraathane", "Restoran & Lokanta"]),
            },
        ],
    },
    {
        slug: "arsa",
        name: "Arsa",
        icon: "🌿",
        children: [
            { slug: "arsa-satilik", name: "Satılık", leaves: makeLeaves("arsa-satilik", ["Arsa"]) },
            { slug: "arsa-kiralik", name: "Kiralık", leaves: makeLeaves("arsa-kiralik", ["Arsa"]) },
            { slug: "arsa-kat-karsiligi-satilik", name: "Kat Karşılığı Satılık", leaves: makeLeaves("arsa-kat-karsiligi-satilik", ["Arsa"]) },
        ],
    },
    {
        slug: "bina",
        name: "Bina",
        icon: "🏗️",
        children: [
            { slug: "bina-satilik", name: "Satılık", leaves: makeLeaves("bina-satilik", ["Komple Bina"]) },
            { slug: "bina-kiralik", name: "Kiralık", leaves: makeLeaves("bina-kiralik", ["Komple Bina"]) },
        ],
    },
    {
        slug: "devre-mulk",
        name: "Devre Mülk",
        icon: "🏖️",
        children: [
            { slug: "devre-mulk-satilik", name: "Satılık", leaves: makeLeaves("devre-mulk-satilik", ["Devre Mülk"]) },
            { slug: "devre-mulk-kiralik", name: "Kiralık", leaves: makeLeaves("devre-mulk-kiralik", ["Devre Mülk"]) },
        ],
    },
    {
        slug: "turistik-tesis",
        name: "Turistik Tesis",
        icon: "🏨",
        children: [
            {
                slug: "turistik-tesis-satilik",
                name: "Satılık",
                leaves: makeLeaves("turistik-tesis-satilik", ["Otel", "Apart Otel", "Butik Otel", "Motel", "Pansiyon", "Kamp Yeri (Mocamp)", "Tatil Köyü"]),
            },
            {
                slug: "turistik-tesis-kiralik",
                name: "Kiralık",
                leaves: makeLeaves("turistik-tesis-kiralik", ["Otel", "Apart Otel", "Butik Otel", "Motel", "Pansiyon", "Kamp Yeri (Mocamp)", "Tatil Köyü"]),
            },
        ],
    },
    // Diğer Ana Kategoriler (düz — leaf = kendisi)
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

// Eski flat liste — seed ve API uyumluluğu için tutulur, zamanla kaldırılabilir.
export const categories = categoryTree.map((c) => ({
    slug: c.slug,
    name: c.name,
    icon: c.icon,
}));
