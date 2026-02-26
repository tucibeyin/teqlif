// Teqlif — Recursive 4-Katmanlı Kategori Ağacı (Flutter)
// Yapı: Gayrimenkul → Konut → Satılık → Daire
// Leaf tespiti: node.children.isEmpty

class CategoryNode {
  final String slug;
  final String name;
  final String icon;
  final List<CategoryNode> children;

  const CategoryNode({
    required this.slug,
    required this.name,
    this.icon = '',
    this.children = const [],
  });

  bool get isLeaf => children.isEmpty;
}

// ─── Yardımcı fonksiyonlar ─────────────────────────────────────────────────

CategoryNode? findNode(String slug, [List<CategoryNode>? nodes]) {
  final list = nodes ?? categoryTree;
  for (final node in list) {
    if (node.slug == slug) return node;
    final found = findNode(slug, node.children);
    if (found != null) return found;
  }
  return null;
}

List<CategoryNode>? findPath(String slug, [List<CategoryNode>? nodes, List<CategoryNode>? path]) {
  final list = nodes ?? categoryTree;
  for (final node in list) {
    final newPath = [...(path ?? []), node];
    if (node.slug == slug) return newPath;
    final found = findPath(slug, node.children, newPath);
    if (found != null) return found;
  }
  return null;
}

// ─── Slug Yardımcısı ───────────────────────────────────────────────────────
String _s(String base, String name) {
  final suffix = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ğüşıöç]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '$base-$suffix';
}

List<CategoryNode> _leaves(String parent, List<String> names) =>
    names.map((n) => CategoryNode(slug: _s(parent, n), name: n)).toList();

// ─── Ağaç Verisi ───────────────────────────────────────────────────────────
const String _GR = 'gayrimenkul';
final String _KNT = _s(_GR, 'konut');
final String _ISY = _s(_GR, 'is-yeri');
final String _ARS = _s(_GR, 'arsa');
final String _BIN = _s(_GR, 'bina');
final String _DVM = _s(_GR, 'devre-mulk');
final String _TRT = _s(_GR, 'turistik-tesis');

final List<CategoryNode> categoryTree = [
  // ── GAYRİMENKUL ─────────────────────────────────────────────────────────
  CategoryNode(slug: _GR, name: 'Gayrimenkul', icon: '🏠', children: [
    // KONUT
    CategoryNode(slug: _KNT, name: 'Konut', icon: '🏠', children: [
      CategoryNode(slug: _s(_KNT, 'satilik'), name: 'Satılık', children: _leaves(_s(_KNT, 'satilik'), ['Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Çiftlik Evi', 'Köşk & Konak', 'Yalı', 'Yalı Dairesi', 'Yazlık', 'Kooperatif'])),
      CategoryNode(slug: _s(_KNT, 'kiralik'), name: 'Kiralık', children: _leaves(_s(_KNT, 'kiralik'), ['Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Çiftlik Evi', 'Köşk & Konak', 'Yalı', 'Yalı Dairesi', 'Yazlık', 'Kooperatif'])),
      CategoryNode(slug: _s(_KNT, 'turistik-gunluk-kiralik'), name: 'Turistik Günlük Kiralık', children: _leaves(_s(_KNT, 'turistik-gunluk-kiralik'), ['Daire', 'Rezidans', 'Müstakil Ev', 'Villa', 'Yazlık', 'Apart Otel', 'Pansiyon'])),
      CategoryNode(slug: _s(_KNT, 'devren-satilik'), name: 'Devren Satılık', children: _leaves(_s(_KNT, 'devren-satilik'), ['Daire', 'Rezidans', 'Müstakil Ev', 'Villa'])),
    ]),
    // İŞ YERİ
    CategoryNode(slug: _ISY, name: 'İş Yeri', icon: '🏢', children: [
      CategoryNode(slug: _s(_ISY, 'satilik'), name: 'Satılık', children: _leaves(_s(_ISY, 'satilik'), ['Büro & Ofis', 'Dükkan & Mağaza', 'Depo & Antrepo', 'Fabrika & Üretim Tesisi', 'Kafe & Bar', 'Restoran & Lokanta', 'AVM', 'Plaza', 'Komple Bina', 'Garaj & Park Yeri'])),
      CategoryNode(slug: _s(_ISY, 'kiralik'), name: 'Kiralık', children: _leaves(_s(_ISY, 'kiralik'), ['Büro & Ofis', 'Dükkan & Mağaza', 'Depo & Antrepo', 'Fabrika & Üretim Tesisi', 'Kafe & Bar', 'Restoran & Lokanta', 'AVM', 'Plaza', 'Komple Bina', 'Garaj & Park Yeri'])),
      CategoryNode(slug: _s(_ISY, 'devren-satilik'), name: 'Devren Satılık', children: _leaves(_s(_ISY, 'devren-satilik'), ['Kafe & Bar', 'Restoran & Lokanta', 'Dükkan & Mağaza', 'Spor Tesisi', 'Pastane, Fırın & Tatlıcı'])),
      CategoryNode(slug: _s(_ISY, 'devren-kiralik'), name: 'Devren Kiralık', children: _leaves(_s(_ISY, 'devren-kiralik'), ['Kafe & Bar', 'Restoran & Lokanta', 'Dükkan & Mağaza'])),
    ]),
    // ARSA
    CategoryNode(slug: _ARS, name: 'Arsa', icon: '🌿', children: [
      CategoryNode(slug: _s(_ARS, 'satilik'), name: 'Satılık'),
      CategoryNode(slug: _s(_ARS, 'kiralik'), name: 'Kiralık'),
      CategoryNode(slug: _s(_ARS, 'kat-karsiligi'), name: 'Kat Karşılığı'),
    ]),
    // BİNA
    CategoryNode(slug: _BIN, name: 'Bina', icon: '🏗️', children: [
      CategoryNode(slug: _s(_BIN, 'satilik'), name: 'Satılık'),
      CategoryNode(slug: _s(_BIN, 'kiralik'), name: 'Kiralık'),
    ]),
    // DEVRE MÜLK
    CategoryNode(slug: _DVM, name: 'Devre Mülk', icon: '🏖️', children: [
      CategoryNode(slug: _s(_DVM, 'satilik'), name: 'Satılık'),
      CategoryNode(slug: _s(_DVM, 'kiralik'), name: 'Kiralık'),
    ]),
    // TURİSTİK TESİS
    CategoryNode(slug: _TRT, name: 'Turistik Tesis', icon: '🏨', children: [
      CategoryNode(slug: _s(_TRT, 'satilik'), name: 'Satılık', children: _leaves(_s(_TRT, 'satilik'), ['Otel', 'Apart Otel', 'Butik Otel', 'Motel', 'Pansiyon', 'Tatil Köyü'])),
      CategoryNode(slug: _s(_TRT, 'kiralik'), name: 'Kiralık', children: _leaves(_s(_TRT, 'kiralik'), ['Otel', 'Apart Otel', 'Butik Otel', 'Motel', 'Pansiyon', 'Tatil Köyü'])),
    ]),
  ]),

  // ── DİĞER KATEGORİLER ───────────────────────────────────────────────────
  CategoryNode(slug: 'elektronik', name: 'Elektronik', icon: '💻'),
  CategoryNode(slug: 'arac', name: 'Araç', icon: '🚗'),
  CategoryNode(slug: 'giyim', name: 'Giyim & Moda', icon: '👗'),
  CategoryNode(slug: 'mobilya', name: 'Mobilya & Ev', icon: '🛋️'),
  CategoryNode(slug: 'spor', name: 'Spor & Outdoor', icon: '⚽'),
  CategoryNode(slug: 'kitap', name: 'Kitap & Hobi', icon: '📚'),
  CategoryNode(slug: 'koleksiyon', name: 'Koleksiyon & Antika', icon: '🏺'),
  CategoryNode(slug: 'cocuk', name: 'Bebek & Çocuk', icon: '🧸'),
  CategoryNode(slug: 'bahce', name: 'Bahçe & Tarım', icon: '🌱'),
  CategoryNode(slug: 'hayvan', name: 'Hayvanlar', icon: '🐾'),
  CategoryNode(slug: 'diger', name: 'Diğer', icon: '📦'),
];
