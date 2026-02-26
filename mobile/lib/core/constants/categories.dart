// Teqlif — 3 Seviyeli Kategori Ağacı (Flutter)
// Yalnızca leaf (yaprak) slug'ı API'ye gönderilir.

class LeafCategory {
  final String slug;
  final String name;
  const LeafCategory({required this.slug, required this.name});
}

class SubCategory {
  final String slug;
  final String name;
  final List<LeafCategory> leaves;
  const SubCategory(
      {required this.slug, required this.name, required this.leaves});
}

class RootCategory {
  final String slug;
  final String name;
  final String icon;
  final List<SubCategory> children;
  const RootCategory(
      {required this.slug,
      required this.name,
      required this.icon,
      required this.children});
}

// ─── Yardımcı ──────────────────────────────────────────────────────────────

String _slugify(String base, String name) {
  final lower = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ğüşıöç]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '$base-$lower';
}

List<LeafCategory> _leaves(String parentSlug, List<String> names) =>
    names.map((n) => LeafCategory(slug: _slugify(parentSlug, n), name: n)).toList();

// ─── Ağaç Verisi ───────────────────────────────────────────────────────────

const _konutSatilik = 'konut-satilik';
const _konutKiralik = 'konut-kiralik';
const _konutTuristik = 'konut-turistik-gunluk-kiralik';
const _konutDevren = 'konut-devren-satilik';
const _isYeriSatilik = 'is-yeri-satilik';
const _isYeriKiralik = 'is-yeri-kiralik';
const _isYeriDevrenSatilik = 'is-yeri-devren-satilik';
const _isYeriDevrenKiralik = 'is-yeri-devren-kiralik';
const _arsaSatilik = 'arsa-satilik';
const _arsaKiralik = 'arsa-kiralik';
const _arsaKat = 'arsa-kat-karsiligi-satilik';
const _binaSatilik = 'bina-satilik';
const _binaKiralik = 'bina-kiralik';
const _devreS = 'devre-mulk-satilik';
const _devreK = 'devre-mulk-kiralik';
const _turistikS = 'turistik-tesis-satilik';
const _turistikK = 'turistik-tesis-kiralik';

final List<RootCategory> categoryTree = [
  RootCategory(
    slug: 'konut',
    name: 'Konut',
    icon: '🏠',
    children: [
      SubCategory(
          slug: _konutSatilik,
          name: 'Satılık',
          leaves: _leaves(_konutSatilik, [
            'Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Çiftlik Evi',
            'Köşk & Konak', 'Yalı', 'Yalı Dairesi', 'Yazlık', 'Kooperatif'
          ])),
      SubCategory(
          slug: _konutKiralik,
          name: 'Kiralık',
          leaves: _leaves(_konutKiralik, [
            'Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Çiftlik Evi',
            'Köşk & Konak', 'Yalı', 'Yalı Dairesi', 'Yazlık', 'Kooperatif'
          ])),
      SubCategory(
          slug: _konutTuristik,
          name: 'Turistik Günlük Kiralık',
          leaves: _leaves(_konutTuristik, [
            'Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Yazlık',
            'Apart Otel', 'Pansiyon'
          ])),
      SubCategory(
          slug: _konutDevren,
          name: 'Devren Satılık Konut',
          leaves: _leaves(_konutDevren,
              ['Daire', 'Rezidans', 'Müstakil Ev', 'Villa'])),
    ],
  ),
  RootCategory(
    slug: 'is-yeri',
    name: 'İş Yeri',
    icon: '🏢',
    children: [
      SubCategory(
          slug: _isYeriSatilik,
          name: 'Satılık',
          leaves: _leaves(_isYeriSatilik, [
            'Akaryakıt İstasyonu', 'Apartman Dairesi', 'Atölye', 'AVM',
            'Büfe', 'Büro & Ofis', 'Çiftlik', 'Depo & Antrepo',
            'Düğün Salonu', 'Dükkan & Mağaza', 'Fabrika & Üretim Tesisi',
            'Garaj & Park Yeri', 'İmalathane', 'İş Hanı Katı & Ofisi',
            'Kafe & Bar', 'Kantin', 'Kıraathane', 'Komple Bina',
            'Otopark & Garaj', 'Oto Yıkama & Kuaför',
            'Pastane, Fırın & Tatlıcı', 'Pazar Yeri', 'Plaza',
            'Plaza Katı & Ofisi', 'Restoran & Lokanta',
            'Rezidans Katı & Ofisi', 'Sağlık Merkezi', 'SPA, Hamam & Sauna',
            'Spor Tesisi', 'Villa', 'Yurt'
          ])),
      SubCategory(
          slug: _isYeriKiralik,
          name: 'Kiralık',
          leaves: _leaves(_isYeriKiralik, [
            'Akaryakıt İstasyonu', 'Apartman Dairesi', 'Atölye', 'AVM',
            'Büfe', 'Büro & Ofis', 'Çiftlik', 'Depo & Antrepo',
            'Düğün Salonu', 'Dükkan & Mağaza', 'Fabrika & Üretim Tesisi',
            'Garaj & Park Yeri', 'İmalathane', 'İş Hanı Katı & Ofisi',
            'Kafe & Bar', 'Kantin', 'Kıraathane', 'Komple Bina',
            'Otopark & Garaj', 'Oto Yıkama & Kuaför',
            'Pastane, Fırın & Tatlıcı', 'Pazar Yeri', 'Plaza',
            'Plaza Katı & Ofisi', 'Restoran & Lokanta',
            'Rezidans Katı & Ofisi', 'Sağlık Merkezi', 'SPA, Hamam & Sauna',
            'Spor Tesisi', 'Villa', 'Yurt'
          ])),
      SubCategory(
          slug: _isYeriDevrenSatilik,
          name: 'Devren Satılık',
          leaves: _leaves(_isYeriDevrenSatilik, [
            'Atölye', 'Büfe', 'Dükkan & Mağaza', 'Fabrika & Üretim Tesisi',
            'İmalathane', 'Kafe & Bar', 'Kıraathane', 'Oto Yıkama & Kuaför',
            'Pastane, Fırın & Tatlıcı', 'Restoran & Lokanta',
            'SPA, Hamam & Sauna', 'Spor Tesisi'
          ])),
      SubCategory(
          slug: _isYeriDevrenKiralik,
          name: 'Devren Kiralık',
          leaves: _leaves(_isYeriDevrenKiralik, [
            'Atölye', 'Büfe', 'Dükkan & Mağaza', 'İmalathane', 'Kafe & Bar',
            'Kıraathane', 'Restoran & Lokanta'
          ])),
    ],
  ),
  RootCategory(
    slug: 'arsa',
    name: 'Arsa',
    icon: '🌿',
    children: [
      SubCategory(
          slug: _arsaSatilik,
          name: 'Satılık',
          leaves: _leaves(_arsaSatilik, ['Arsa'])),
      SubCategory(
          slug: _arsaKiralik,
          name: 'Kiralık',
          leaves: _leaves(_arsaKiralik, ['Arsa'])),
      SubCategory(
          slug: _arsaKat,
          name: 'Kat Karşılığı Satılık',
          leaves: _leaves(_arsaKat, ['Arsa'])),
    ],
  ),
  RootCategory(
    slug: 'bina',
    name: 'Bina',
    icon: '🏗️',
    children: [
      SubCategory(
          slug: _binaSatilik,
          name: 'Satılık',
          leaves: _leaves(_binaSatilik, ['Komple Bina'])),
      SubCategory(
          slug: _binaKiralik,
          name: 'Kiralık',
          leaves: _leaves(_binaKiralik, ['Komple Bina'])),
    ],
  ),
  RootCategory(
    slug: 'devre-mulk',
    name: 'Devre Mülk',
    icon: '🏖️',
    children: [
      SubCategory(
          slug: _devreS,
          name: 'Satılık',
          leaves: _leaves(_devreS, ['Devre Mülk'])),
      SubCategory(
          slug: _devreK,
          name: 'Kiralık',
          leaves: _leaves(_devreK, ['Devre Mülk'])),
    ],
  ),
  RootCategory(
    slug: 'turistik-tesis',
    name: 'Turistik Tesis',
    icon: '🏨',
    children: [
      SubCategory(
          slug: _turistikS,
          name: 'Satılık',
          leaves: _leaves(_turistikS, [
            'Otel', 'Apart Otel', 'Butik Otel', 'Motel', 'Pansiyon',
            'Kamp Yeri (Mocamp)', 'Tatil Köyü'
          ])),
      SubCategory(
          slug: _turistikK,
          name: 'Kiralık',
          leaves: _leaves(_turistikK, [
            'Otel', 'Apart Otel', 'Butik Otel', 'Motel', 'Pansiyon',
            'Kamp Yeri (Mocamp)', 'Tatil Köyü'
          ])),
    ],
  ),
  // ── Diğer kategoriler (leaf = root, children boş) ──────────────────────
  RootCategory(slug: 'elektronik', name: 'Elektronik', icon: '💻', children: []),
  RootCategory(slug: 'arac', name: 'Araç', icon: '🚗', children: []),
  RootCategory(slug: 'giyim', name: 'Giyim & Moda', icon: '👗', children: []),
  RootCategory(slug: 'mobilya', name: 'Mobilya & Ev', icon: '🛋️', children: []),
  RootCategory(slug: 'spor', name: 'Spor & Outdoor', icon: '⚽', children: []),
  RootCategory(slug: 'kitap', name: 'Kitap & Hobi', icon: '📚', children: []),
  RootCategory(slug: 'koleksiyon', name: 'Koleksiyon & Antika', icon: '🏺', children: []),
  RootCategory(slug: 'cocuk', name: 'Bebek & Çocuk', icon: '🧸', children: []),
  RootCategory(slug: 'bahce', name: 'Bahçe & Tarım', icon: '🌱', children: []),
  RootCategory(slug: 'hayvan', name: 'Hayvanlar', icon: '🐾', children: []),
  RootCategory(slug: 'diger', name: 'Diğer', icon: '📦', children: []),
];

/// Bir slug'dan geriye doğru root/sub/leaf bulur
({String root, String sub, String leaf}) findSelections(String leafSlug) {
  for (final root in categoryTree) {
    if (root.slug == leafSlug) return (root: root.slug, sub: '', leaf: '');
    for (final sub in root.children) {
      if (sub.slug == leafSlug) return (root: root.slug, sub: sub.slug, leaf: '');
      for (final leaf in sub.leaves) {
        if (leaf.slug == leafSlug) {
          return (root: root.slug, sub: sub.slug, leaf: leaf.slug);
        }
      }
    }
  }
  return (root: '', sub: '', leaf: '');
}
