// Subcategory definitions and dynamic extra-field specs for the Create Listing form.
//
// Stored values (FieldOption.value) are normalized snake_case strings written
// into extra_fields JSONB. Display labels are Turkish for the pilot; proper
// i18n via ARB keys is a planned follow-up.

// ── Types ─────────────────────────────────────────────────────────────────────

enum ExtraFieldType { text, number, dropdown, multiselect }

class FieldOption {
  final String value;
  final String label;
  final String? parentOptionValue;
  // true = selecting this clears all other multiselect selections
  final bool isExclusive;

  const FieldOption(this.value, this.label, [this.parentOptionValue, this.isExclusive = false]);

  factory FieldOption.fromJson(Map<String, dynamic> j) {
    final pov = j['parent_option_value'] as String?;
    final exclusive = pov == '__excl__';
    return FieldOption(
      j['value'] as String,
      j['label'] as String,
      exclusive ? null : pov,
      exclusive,
    );
  }
}

class ExtraFieldDef {
  final String key;
  final String labelKey;
  final ExtraFieldType type;
  final bool optional;
  final List<FieldOption> options;
  final String? unit;
  final String? dependsOn;
  final Map<String, List<FieldOption>>? conditionalOptions;

  const ExtraFieldDef({
    required this.key,
    required this.labelKey,
    this.type = ExtraFieldType.text,
    this.optional = false,
    this.options = const [],
    this.unit,
    this.dependsOn,
    this.conditionalOptions,
  });

  factory ExtraFieldDef.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? 'text';
    final type = switch (typeStr) {
      'number'      => ExtraFieldType.number,
      'dropdown'    => ExtraFieldType.dropdown,
      'multiselect' => ExtraFieldType.multiselect,
      _             => ExtraFieldType.text,
    };

    final allOptions = (j['options'] as List<dynamic>? ?? [])
        .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
        .toList();

    // Include top-level options (null parent) and group-tagged options ('grp:' prefix).
    // Conditional dropdown options (real parent value like 'bmw') are excluded here.
    final topOptions = allOptions
        .where((o) =>
            o.parentOptionValue == null ||
            (o.parentOptionValue?.startsWith('grp:') ?? false))
        .toList();

    Map<String, List<FieldOption>>? conditionalOptions;
    final condEntries = allOptions.where((o) => o.parentOptionValue != null);
    if (condEntries.isNotEmpty) {
      conditionalOptions = <String, List<FieldOption>>{};
      for (final opt in condEntries) {
        (conditionalOptions[opt.parentOptionValue!] ??= []).add(opt);
      }
    }

    return ExtraFieldDef(
      key: j['key'] as String,
      labelKey: j['label_key'] as String,
      type: type,
      optional: !(j['required'] as bool? ?? true),
      options: topOptions,
      unit: j['unit'] as String?,
      dependsOn: j['depends_on'] as String?,
      conditionalOptions: conditionalOptions,
    );
  }
}

// ── Shared option lists ───────────────────────────────────────────────────────

const _renk = [
  FieldOption('white', 'Beyaz'),
  FieldOption('gray', 'Gri'),
  FieldOption('black', 'Siyah'),
  FieldOption('blue', 'Mavi'),
  FieldOption('red', 'Kırmızı'),
  FieldOption('green', 'Yeşil'),
  FieldOption('yellow', 'Sarı'),
  FieldOption('orange', 'Turuncu'),
  FieldOption('purple', 'Mor'),
  FieldOption('pink', 'Pembe'),
  FieldOption('brown', 'Kahverengi'),
  FieldOption('beige', 'Bej'),
  FieldOption('gold', 'Altın'),
  FieldOption('silver', 'Gümüş'),
  FieldOption('other', 'Diğer'),
];

const _yakitTipi = [
  FieldOption('gasoline', 'Benzin'),
  FieldOption('diesel', 'Dizel'),
  FieldOption('lpg', 'LPG'),
  FieldOption('hybrid', 'Hibrit'),
  FieldOption('electric', 'Elektrik'),
  FieldOption('other', 'Diğer'),
];

const _vites = [
  FieldOption('manual', 'Manuel'),
  FieldOption('automatic', 'Otomatik'),
  FieldOption('semi_automatic', 'Yarı Otomatik'),
];

const _vitesManuelDefault = [
  FieldOption('manual', 'Manuel'),
  FieldOption('automatic', 'Otomatik'),
  FieldOption('semi_automatic', 'Yarı Otomatik'),
];

const _kasaTipi = [
  FieldOption('sedan', 'Sedan'),
  FieldOption('hatchback', 'Hatchback'),
  FieldOption('suv', 'SUV'),
  FieldOption('station_wagon', 'Station Wagon'),
  FieldOption('coupe', 'Coupe'),
  FieldOption('cabriolet', 'Cabriolet'),
  FieldOption('pickup', 'Pickup'),
  FieldOption('van', 'Van'),
  FieldOption('minibus', 'Minibüs'),
  FieldOption('other', 'Diğer'),
];

const _markaArac = [
  FieldOption('alfa_romeo', 'Alfa Romeo'),
  FieldOption('audi', 'Audi'),
  FieldOption('bmw', 'BMW'),
  FieldOption('chevrolet', 'Chevrolet'),
  FieldOption('citroen', 'Citroën'),
  FieldOption('dacia', 'Dacia'),
  FieldOption('fiat', 'Fiat'),
  FieldOption('ford', 'Ford'),
  FieldOption('honda', 'Honda'),
  FieldOption('hyundai', 'Hyundai'),
  FieldOption('jeep', 'Jeep'),
  FieldOption('kia', 'Kia'),
  FieldOption('land_rover', 'Land Rover'),
  FieldOption('mazda', 'Mazda'),
  FieldOption('mercedes', 'Mercedes-Benz'),
  FieldOption('mitsubishi', 'Mitsubishi'),
  FieldOption('nissan', 'Nissan'),
  FieldOption('opel', 'Opel'),
  FieldOption('peugeot', 'Peugeot'),
  FieldOption('porsche', 'Porsche'),
  FieldOption('renault', 'Renault'),
  FieldOption('seat', 'SEAT'),
  FieldOption('skoda', 'Skoda'),
  FieldOption('subaru', 'Subaru'),
  FieldOption('tesla', 'Tesla'),
  FieldOption('togg', 'TOGG'),
  FieldOption('toyota', 'Toyota'),
  FieldOption('volkswagen', 'Volkswagen'),
  FieldOption('volvo', 'Volvo'),
  FieldOption('other', 'Diğer'),
];

const _markaElektrikli = [
  FieldOption('tesla', 'Tesla'),
  FieldOption('togg', 'TOGG'),
  FieldOption('bmw', 'BMW'),
  FieldOption('audi', 'Audi'),
  FieldOption('hyundai', 'Hyundai'),
  FieldOption('kia', 'Kia'),
  FieldOption('volkswagen', 'Volkswagen'),
  FieldOption('nissan', 'Nissan'),
  FieldOption('renault', 'Renault'),
  FieldOption('porsche', 'Porsche'),
  FieldOption('mercedes', 'Mercedes-Benz'),
  FieldOption('peugeot', 'Peugeot'),
  FieldOption('other', 'Diğer'),
];

const _markaMoto = [
  FieldOption('honda', 'Honda'),
  FieldOption('yamaha', 'Yamaha'),
  FieldOption('kawasaki', 'Kawasaki'),
  FieldOption('suzuki', 'Suzuki'),
  FieldOption('bmw', 'BMW'),
  FieldOption('ducati', 'Ducati'),
  FieldOption('harley', 'Harley-Davidson'),
  FieldOption('royal_enfield', 'Royal Enfield'),
  FieldOption('ktm', 'KTM'),
  FieldOption('triumph', 'Triumph'),
  FieldOption('aprilia', 'Aprilia'),
  FieldOption('other', 'Diğer'),
];

const _motoTip = [
  FieldOption('naked', 'Naked'),
  FieldOption('sport', 'Sport'),
  FieldOption('touring', 'Touring'),
  FieldOption('enduro', 'Enduro'),
  FieldOption('scooter', 'Scooter'),
  FieldOption('chopper', 'Chopper'),
  FieldOption('adventure', 'Adventure'),
  FieldOption('other', 'Diğer'),
];

const _hasar = [
  FieldOption('painted',             'Boyalı'),
  FieldOption('accident',             'Kazalı'),
  // 'grp:damage_level' → mutually exclusive with each other within this group
  FieldOption('damage_record',      'Hasar Kayıtlı',      'grp:damage_level'),
  FieldOption('heavy_damage_record', 'Ağır Hasar Kayıtlı', 'grp:damage_level'),
  FieldOption('flawless',            'Hatasız',             null, true), // exclusive: clears all
];

const _markaKamyon = [
  FieldOption('ford', 'Ford'),
  FieldOption('fiat', 'Fiat'),
  FieldOption('volkswagen', 'Volkswagen'),
  FieldOption('mercedes', 'Mercedes-Benz'),
  FieldOption('renault', 'Renault'),
  FieldOption('opel', 'Opel'),
  FieldOption('peugeot', 'Peugeot'),
  FieldOption('isuzu', 'Isuzu'),
  FieldOption('iveco', 'Iveco'),
  FieldOption('man', 'MAN'),
  FieldOption('daf', 'DAF'),
  FieldOption('volvo', 'Volvo'),
  FieldOption('scania', 'Scania'),
  FieldOption('other', 'Diğer'),
];

const _markaTaktor = [
  FieldOption('new_holland', 'New Holland'),
  FieldOption('john_deere', 'John Deere'),
  FieldOption('massey_ferguson', 'Massey Ferguson'),
  FieldOption('kubota', 'Kubota'),
  FieldOption('fendt', 'Fendt'),
  FieldOption('case', 'Case'),
  FieldOption('tumosan', 'Tümosan'),
  FieldOption('other', 'Diğer'),
];

const _tekneTip = [
  FieldOption('motorboat', 'Motor Tekne'),
  FieldOption('sailboat', 'Yelkenli'),
  FieldOption('speedboat', 'Sürat Teknesi'),
  FieldOption('cutter', 'Kotra'),
  FieldOption('kayak', 'Kanotaj'),
  FieldOption('jet_ski', 'Jet Ski'),
  FieldOption('other', 'Diğer'),
];

const _tekneYakit = [
  FieldOption('gasoline', 'Benzin'),
  FieldOption('diesel', 'Dizel'),
  FieldOption('electric', 'Elektrik'),
  FieldOption('sail', 'Yelken'),
  FieldOption('other', 'Diğer'),
];

// Elektronik
const _markaTelefon = [
  FieldOption('apple', 'Apple'),
  FieldOption('samsung', 'Samsung'),
  FieldOption('xiaomi', 'Xiaomi'),
  FieldOption('huawei', 'Huawei'),
  FieldOption('oneplus', 'OnePlus'),
  FieldOption('google', 'Google'),
  FieldOption('oppo', 'Oppo'),
  FieldOption('realme', 'Realme'),
  FieldOption('nokia', 'Nokia'),
  FieldOption('motorola', 'Motorola'),
  FieldOption('other', 'Diğer'),
];

const _depolamaKucuk = [
  FieldOption('16gb', '16 GB'),
  FieldOption('32gb', '32 GB'),
  FieldOption('64gb', '64 GB'),
  FieldOption('128gb', '128 GB'),
  FieldOption('256gb', '256 GB'),
  FieldOption('512gb', '512 GB'),
  FieldOption('1tb', '1 TB'),
  FieldOption('2tb', '2 TB'),
];

const _ram = [
  FieldOption('2gb', '2 GB'),
  FieldOption('3gb', '3 GB'),
  FieldOption('4gb', '4 GB'),
  FieldOption('6gb', '6 GB'),
  FieldOption('8gb', '8 GB'),
  FieldOption('12gb', '12 GB'),
  FieldOption('16gb', '16 GB'),
  FieldOption('32gb', '32 GB'),
  FieldOption('64gb', '64 GB'),
];

const _markaBilgisayar = [
  FieldOption('apple', 'Apple'),
  FieldOption('asus', 'Asus'),
  FieldOption('lenovo', 'Lenovo'),
  FieldOption('dell', 'Dell'),
  FieldOption('hp', 'HP'),
  FieldOption('msi', 'MSI'),
  FieldOption('acer', 'Acer'),
  FieldOption('toshiba', 'Toshiba'),
  FieldOption('samsung', 'Samsung'),
  FieldOption('huawei', 'Huawei'),
  FieldOption('other', 'Diğer'),
];

const _islemci = [
  FieldOption('intel_i3', 'Intel Core i3'),
  FieldOption('intel_i5', 'Intel Core i5'),
  FieldOption('intel_i7', 'Intel Core i7'),
  FieldOption('intel_i9', 'Intel Core i9'),
  FieldOption('amd_r5', 'AMD Ryzen 5'),
  FieldOption('amd_r7', 'AMD Ryzen 7'),
  FieldOption('amd_r9', 'AMD Ryzen 9'),
  FieldOption('apple_m1', 'Apple M1'),
  FieldOption('apple_m2', 'Apple M2'),
  FieldOption('apple_m3', 'Apple M3'),
  FieldOption('apple_m4', 'Apple M4'),
  FieldOption('other', 'Diğer'),
];

const _ekranBoyutu = [
  FieldOption('11', '11"'),
  FieldOption('13', '13"'),
  FieldOption('14', '14"'),
  FieldOption('15', '15"'),
  FieldOption('16', '16"'),
  FieldOption('17', '17"'),
  FieldOption('24', '24"'),
  FieldOption('27', '27"'),
  FieldOption('32', '32"'),
  FieldOption('other', 'Diğer'),
];

const _kameraTip = [
  FieldOption('dslr', 'DSLR'),
  FieldOption('mirrorless', 'Mirrorless'),
  FieldOption('compact', 'Kompakt'),
  FieldOption('action', 'Action Kamera'),
  FieldOption('video', 'Video Kamera'),
  FieldOption('other', 'Diğer'),
];

const _markaKamera = [
  FieldOption('canon', 'Canon'),
  FieldOption('nikon', 'Nikon'),
  FieldOption('sony', 'Sony'),
  FieldOption('fujifilm', 'Fujifilm'),
  FieldOption('panasonic', 'Panasonic'),
  FieldOption('olympus', 'Olympus'),
  FieldOption('gopro', 'GoPro'),
  FieldOption('other', 'Diğer'),
];

const _konsolMarka = [
  FieldOption('playstation', 'PlayStation'),
  FieldOption('xbox', 'Xbox'),
  FieldOption('nintendo', 'Nintendo'),
  FieldOption('other', 'Diğer'),
];

const _konsolModel = [
  FieldOption('ps5', 'PlayStation 5'),
  FieldOption('ps4', 'PlayStation 4'),
  FieldOption('ps4_pro', 'PlayStation 4 Pro'),
  FieldOption('xbox_series_x', 'Xbox Series X'),
  FieldOption('xbox_series_s', 'Xbox Series S'),
  FieldOption('xbox_one', 'Xbox One'),
  FieldOption('nintendo_switch', 'Nintendo Switch'),
  FieldOption('nintendo_switch_lite', 'Nintendo Switch Lite'),
  FieldOption('other', 'Diğer'),
];

// Emlak
const _odaSayisi = [
  FieldOption('1+0', '1+0 Stüdyo'),
  FieldOption('1+1', '1+1'),
  FieldOption('2+1', '2+1'),
  FieldOption('3+1', '3+1'),
  FieldOption('4+1', '4+1'),
  FieldOption('5+1', '5+1'),
  FieldOption('6+1', '6+1 ve üzeri'),
];

const _binaYasi = [
  FieldOption('new_build', 'Sıfır (0)'),
  FieldOption('1_5', '1–5 yıl'),
  FieldOption('6_10', '6–10 yıl'),
  FieldOption('11_15', '11–15 yıl'),
  FieldOption('16_20', '16–20 yıl'),
  FieldOption('21_plus', '21 yıl ve üzeri'),
];

const _isitma = [
  FieldOption('combi_boiler', 'Kombi'),
  FieldOption('central_gas', 'Doğalgaz (Merkezi)'),
  FieldOption('stove', 'Soba'),
  FieldOption('air_conditioning', 'Klima'),
  FieldOption('underfloor_heating', 'Yerden Isıtma'),
  FieldOption('none', 'Yok'),
];

const _esyaDurumu = [
  FieldOption('furnished', 'Eşyalı'),
  FieldOption('semi_furnished', 'Yarı Eşyalı'),
  FieldOption('empty', 'Boş'),
];

const _varYok = [
  FieldOption('yes', 'Var'),
  FieldOption('no', 'Yok'),
];

const _tapuDurumu = [
  FieldOption('condominium', 'Kat Mülkiyeti'),
  FieldOption('floor_easement', 'Kat İrtifakı'),
  FieldOption('shared_ownership', 'Hisseli Tapu'),
  FieldOption('land_title', 'Arsa Tapusu'),
  FieldOption('other', 'Diğer'),
];

const _arsaKullanimDurumu = [
  FieldOption('residential', 'Konut İmarlı'),
  FieldOption('commercial', 'Ticari İmarlı'),
  FieldOption('agricultural', 'Tarımsal'),
  FieldOption('industrial', 'Sanayi'),
  FieldOption('other', 'Diğer'),
];

// Giyim
const _bedenKadin = [
  FieldOption('xxs', 'XXS'),
  FieldOption('xs', 'XS'),
  FieldOption('s', 'S'),
  FieldOption('m', 'M'),
  FieldOption('l', 'L'),
  FieldOption('xl', 'XL'),
  FieldOption('xxl', 'XXL'),
  FieldOption('xxxl', 'XXXL'),
  FieldOption('4xl', '4XL'),
];

const _bedenCocuk = [
  FieldOption('0_3m', '0–3 Ay'),
  FieldOption('3_6m', '3–6 Ay'),
  FieldOption('6_12m', '6–12 Ay'),
  FieldOption('1_2y', '1–2 Yaş'),
  FieldOption('3_4y', '3–4 Yaş'),
  FieldOption('5_6y', '5–6 Yaş'),
  FieldOption('7_8y', '7–8 Yaş'),
  FieldOption('9_10y', '9–10 Yaş'),
  FieldOption('11_12y', '11–12 Yaş'),
  FieldOption('13_14y', '13–14 Yaş'),
];

const _numara = [
  FieldOption('35', '35'),
  FieldOption('36', '36'),
  FieldOption('37', '37'),
  FieldOption('38', '38'),
  FieldOption('39', '39'),
  FieldOption('40', '40'),
  FieldOption('41', '41'),
  FieldOption('42', '42'),
  FieldOption('43', '43'),
  FieldOption('44', '44'),
  FieldOption('45', '45'),
  FieldOption('46', '46'),
  FieldOption('47', '47'),
];

const _ayakkabiTip = [
  FieldOption('sneaker', 'Spor / Sneaker'),
  FieldOption('formal', 'Klasik'),
  FieldOption('boot', 'Bot'),
  FieldOption('sandal', 'Sandalet'),
  FieldOption('slipper', 'Terlik'),
  FieldOption('heeled', 'Topuklu'),
  FieldOption('other', 'Diğer'),
];

const _cantaMalzeme = [
  FieldOption('leather', 'Deri'),
  FieldOption('faux_leather', 'Suni Deri'),
  FieldOption('fabric', 'Kumaş'),
  FieldOption('canvas', 'Kanvas'),
  FieldOption('other', 'Diğer'),
];

const _takiMalzeme = [
  FieldOption('gold', 'Altın'),
  FieldOption('silver', 'Gümüş'),
  FieldOption('platinum', 'Platin'),
  FieldOption('diamond', 'Elmas'),
  FieldOption('natural_stone', 'Doğal Taş'),
  FieldOption('other', 'Diğer'),
];

const _altinAyar = [
  FieldOption('8', '8 Ayar'),
  FieldOption('14', '14 Ayar'),
  FieldOption('18', '18 Ayar'),
  FieldOption('22', '22 Ayar'),
  FieldOption('24', '24 Ayar'),
];

const _gumusAyar = [
  FieldOption('925', '925 Ayar (Sterlin)'),
  FieldOption('800', '800 Ayar'),
  FieldOption('other', 'Diğer'),
];

const _saatCinsiyet = [
  FieldOption('male', 'Erkek'),
  FieldOption('female', 'Kadın'),
  FieldOption('unisex', 'Unisex'),
];

const _markaSaat = [
  FieldOption('rolex', 'Rolex'),
  FieldOption('omega', 'Omega'),
  FieldOption('seiko', 'Seiko'),
  FieldOption('casio', 'Casio'),
  FieldOption('tissot', 'Tissot'),
  FieldOption('tag_heuer', 'TAG Heuer'),
  FieldOption('fossil', 'Fossil'),
  FieldOption('swatch', 'Swatch'),
  FieldOption('other', 'Diğer'),
];

// Ev & Yaşam
const _mobilyaTip = [
  FieldOption('sofa', 'Koltuk / Kanepe'),
  FieldOption('bed', 'Yatak'),
  FieldOption('table', 'Masa'),
  FieldOption('chair', 'Sandalye'),
  FieldOption('wardrobe', 'Dolap / Gardırop'),
  FieldOption('shelf', 'Raf / Kitaplık'),
  FieldOption('coffee_table', 'Sehpa'),
  FieldOption('other', 'Diğer'),
];

const _mobilyaMalzeme = [
  FieldOption('wood', 'Ahşap'),
  FieldOption('metal', 'Metal'),
  FieldOption('plastic', 'Plastik'),
  FieldOption('glass', 'Cam'),
  FieldOption('leather', 'Deri'),
  FieldOption('fabric', 'Kumaş'),
  FieldOption('other', 'Diğer'),
];

const _evTekstilTip = [
  FieldOption('bedding_set', 'Nevresim Takımı'),
  FieldOption('quilt', 'Yorgan'),
  FieldOption('pillow', 'Yastık'),
  FieldOption('towel', 'Havlu'),
  FieldOption('curtain', 'Perde'),
  FieldOption('rug', 'Halı / Kilim'),
  FieldOption('other', 'Diğer'),
];

const _aydinlatmaTip = [
  FieldOption('chandelier', 'Avize'),
  FieldOption('lampshade', 'Abajur'),
  FieldOption('desk_lamp', 'Masa Lambası'),
  FieldOption('wall_lamp', 'Aplik'),
  FieldOption('floor_lamp', 'Ayak Lambası'),
  FieldOption('other', 'Diğer'),
];

// Spor
const _bisikletTip = [
  FieldOption('mountain', 'Dağ Bisikleti'),
  FieldOption('road', 'Yol Bisikleti'),
  FieldOption('city', 'Şehir Bisikleti'),
  FieldOption('bmx', 'BMX'),
  FieldOption('electric_bike', 'Elektrikli Bisiklet'),
  FieldOption('folding', 'Katlanan Bisiklet'),
  FieldOption('other', 'Diğer'),
];

const _markaBisiklet = [
  FieldOption('giant', 'Giant'),
  FieldOption('trek', 'Trek'),
  FieldOption('specialized', 'Specialized'),
  FieldOption('bianchi', 'Bianchi'),
  FieldOption('scott', 'Scott'),
  FieldOption('merida', 'Merida'),
  FieldOption('cannondale', 'Cannondale'),
  FieldOption('other', 'Diğer'),
];

const _jantBoyutu = [
  FieldOption('20', '20"'),
  FieldOption('24', '24"'),
  FieldOption('26', '26"'),
  FieldOption('27.5', '27.5"'),
  FieldOption('28', '28"'),
  FieldOption('29', '29"'),
];

const _sporDali = [
  FieldOption('football', 'Futbol'),
  FieldOption('basketball', 'Basketbol'),
  FieldOption('volleyball', 'Voleybol'),
  FieldOption('tennis', 'Tenis'),
  FieldOption('swimming', 'Yüzme'),
  FieldOption('running', 'Koşu'),
  FieldOption('boxing', 'Boks / Muay Thai'),
  FieldOption('yoga', 'Yoga / Pilates'),
  FieldOption('outdoor', 'Doğa Sporları'),
  FieldOption('other', 'Diğer'),
];

// Diğer
const _evcilHayvanTip = [
  FieldOption('dog', 'Köpek'),
  FieldOption('cat', 'Kedi'),
  FieldOption('bird', 'Kuş'),
  FieldOption('fish', 'Balık'),
  FieldOption('hamster', 'Hamster'),
  FieldOption('rabbit', 'Tavşan'),
  FieldOption('other', 'Diğer'),
];

const _muzikAletiTip = [
  FieldOption('guitar', 'Gitar'),
  FieldOption('piano', 'Piyano / Klavye'),
  FieldOption('drums', 'Davul / Perküsyon'),
  FieldOption('violin', 'Keman'),
  FieldOption('saz', 'Saz / Bağlama'),
  FieldOption('flute', 'Flüt'),
  FieldOption('other', 'Diğer'),
];

const _fotoEkipmanTip = [
  FieldOption('camera', 'Kamera'),
  FieldOption('lens', 'Lens'),
  FieldOption('tripod', 'Tripod'),
  FieldOption('drone', 'Drone'),
  FieldOption('flash', 'Flaş / Işık'),
  FieldOption('other', 'Diğer'),
];

// ── Brand → model maps (conditionalOptions) ───────────────────────────────────

const _modellerTelefon = <String, List<FieldOption>>{
  'apple': [
    FieldOption('iphone_13', 'iPhone 13'),
    FieldOption('iphone_14', 'iPhone 14'),
    FieldOption('iphone_15', 'iPhone 15'),
    FieldOption('iphone_15_pro', 'iPhone 15 Pro'),
    FieldOption('iphone_16', 'iPhone 16'),
  ],
  'samsung': [
    FieldOption('galaxy_s23', 'Galaxy S23'),
    FieldOption('galaxy_s24', 'Galaxy S24'),
    FieldOption('galaxy_s24_ultra', 'Galaxy S24 Ultra'),
    FieldOption('galaxy_a54', 'Galaxy A54'),
    FieldOption('galaxy_a35', 'Galaxy A35'),
  ],
  'xiaomi': [
    FieldOption('redmi_note_13', 'Redmi Note 13'),
    FieldOption('poco_x6_pro', 'Poco X6 Pro'),
    FieldOption('14t_pro', '14T Pro'),
    FieldOption('redmi_12', 'Redmi 12'),
    FieldOption('poco_m6_pro', 'Poco M6 Pro'),
  ],
  'huawei': [
    FieldOption('p50', 'P50'),
    FieldOption('p60_pro', 'P60 Pro'),
    FieldOption('nova_11', 'Nova 11'),
    FieldOption('mate_60_pro', 'Mate 60 Pro'),
    FieldOption('p40_lite', 'P40 Lite'),
  ],
  'oneplus': [
    FieldOption('oneplus_12', 'OnePlus 12'),
    FieldOption('oneplus_11', 'OnePlus 11'),
    FieldOption('nord_3', 'Nord 3'),
    FieldOption('oneplus_12r', 'OnePlus 12R'),
    FieldOption('nord_ce3', 'Nord CE 3'),
  ],
  'google': [
    FieldOption('pixel_7a', 'Pixel 7a'),
    FieldOption('pixel_8', 'Pixel 8'),
    FieldOption('pixel_8_pro', 'Pixel 8 Pro'),
    FieldOption('pixel_9', 'Pixel 9'),
    FieldOption('pixel_9_pro', 'Pixel 9 Pro'),
  ],
  'oppo': [
    FieldOption('find_x7', 'Find X7'),
    FieldOption('reno_11', 'Reno 11'),
    FieldOption('a78', 'A78'),
    FieldOption('find_x6', 'Find X6'),
    FieldOption('reno_10_pro', 'Reno 10 Pro'),
  ],
  'realme': [
    FieldOption('12_pro_plus', '12 Pro+'),
    FieldOption('gt_5', 'GT 5'),
    FieldOption('c67', 'C67'),
    FieldOption('11_pro_plus', '11 Pro+'),
    FieldOption('gt_neo_5', 'GT Neo 5'),
  ],
  'nokia': [
    FieldOption('g42', 'G42'),
    FieldOption('c32', 'C32'),
    FieldOption('g21', 'G21'),
    FieldOption('xr21', 'XR21'),
    FieldOption('g60', 'G60'),
  ],
  'motorola': [
    FieldOption('moto_g84', 'Moto G84'),
    FieldOption('edge_40', 'Edge 40'),
    FieldOption('moto_g54', 'Moto G54'),
    FieldOption('edge_50_pro', 'Edge 50 Pro'),
    FieldOption('razr_40', 'Razr 40'),
  ],
};

const _modellerArac = <String, List<FieldOption>>{
  'alfa_romeo': [
    FieldOption('giulia', 'Giulia'),
    FieldOption('stelvio', 'Stelvio'),
    FieldOption('giulietta', 'Giulietta'),
    FieldOption('tonale', 'Tonale'),
    FieldOption('156', '156'),
  ],
  'audi': [
    FieldOption('a3', 'A3'),
    FieldOption('a4', 'A4'),
    FieldOption('a6', 'A6'),
    FieldOption('q3', 'Q3'),
    FieldOption('q5', 'Q5'),
  ],
  'bmw': [
    FieldOption('1_series', '1 Serisi'),
    FieldOption('3_series', '3 Serisi'),
    FieldOption('5_series', '5 Serisi'),
    FieldOption('x3', 'X3'),
    FieldOption('x5', 'X5'),
  ],
  'chevrolet': [
    FieldOption('captiva', 'Captiva'),
    FieldOption('malibu', 'Malibu'),
    FieldOption('cruze', 'Cruze'),
    FieldOption('spark', 'Spark'),
    FieldOption('orlando', 'Orlando'),
  ],
  'citroen': [
    FieldOption('c3', 'C3'),
    FieldOption('c4', 'C4'),
    FieldOption('c3_aircross', 'C3 Aircross'),
    FieldOption('c5_aircross', 'C5 Aircross'),
    FieldOption('berlingo', 'Berlingo'),
  ],
  'dacia': [
    FieldOption('duster', 'Duster'),
    FieldOption('sandero', 'Sandero'),
    FieldOption('logan', 'Logan'),
    FieldOption('jogger', 'Jogger'),
    FieldOption('spring', 'Spring'),
  ],
  'fiat': [
    FieldOption('egea', 'Egea'),
    FieldOption('panda', 'Panda'),
    FieldOption('500', '500'),
    FieldOption('tipo', 'Tipo'),
    FieldOption('doblo', 'Doblò'),
  ],
  'ford': [
    FieldOption('focus', 'Focus'),
    FieldOption('fiesta', 'Fiesta'),
    FieldOption('kuga', 'Kuga'),
    FieldOption('puma', 'Puma'),
    FieldOption('transit_custom', 'Transit Custom'),
  ],
  'honda': [
    FieldOption('civic', 'Civic'),
    FieldOption('cr_v', 'CR-V'),
    FieldOption('hr_v', 'HR-V'),
    FieldOption('jazz', 'Jazz'),
    FieldOption('accord', 'Accord'),
  ],
  'hyundai': [
    FieldOption('i20', 'i20'),
    FieldOption('i30', 'i30'),
    FieldOption('tucson', 'Tucson'),
    FieldOption('kona', 'Kona'),
    FieldOption('santa_fe', 'Santa Fe'),
  ],
  'jeep': [
    FieldOption('renegade', 'Renegade'),
    FieldOption('compass', 'Compass'),
    FieldOption('wrangler', 'Wrangler'),
    FieldOption('cherokee', 'Cherokee'),
    FieldOption('grand_cherokee', 'Grand Cherokee'),
  ],
  'kia': [
    FieldOption('sportage', 'Sportage'),
    FieldOption('ceed', 'Ceed'),
    FieldOption('stonic', 'Stonic'),
    FieldOption('rio', 'Rio'),
    FieldOption('sorento', 'Sorento'),
  ],
  'land_rover': [
    FieldOption('defender', 'Defender'),
    FieldOption('discovery', 'Discovery'),
    FieldOption('range_rover', 'Range Rover'),
    FieldOption('discovery_sport', 'Discovery Sport'),
    FieldOption('range_rover_sport', 'Range Rover Sport'),
  ],
  'mazda': [
    FieldOption('cx_5', 'CX-5'),
    FieldOption('mazda3', 'Mazda3'),
    FieldOption('cx_30', 'CX-30'),
    FieldOption('mazda6', 'Mazda6'),
    FieldOption('mx_5', 'MX-5'),
  ],
  'mercedes': [
    FieldOption('a_series', 'A Serisi'),
    FieldOption('c_series', 'C Serisi'),
    FieldOption('e_series', 'E Serisi'),
    FieldOption('glc', 'GLC'),
    FieldOption('gle', 'GLE'),
  ],
  'mitsubishi': [
    FieldOption('outlander', 'Outlander'),
    FieldOption('eclipse_cross', 'Eclipse Cross'),
    FieldOption('asx', 'ASX'),
    FieldOption('l200', 'L200'),
    FieldOption('pajero', 'Pajero'),
  ],
  'nissan': [
    FieldOption('qashqai', 'Qashqai'),
    FieldOption('juke', 'Juke'),
    FieldOption('micra', 'Micra'),
    FieldOption('x_trail', 'X-Trail'),
    FieldOption('leaf', 'Leaf'),
  ],
  'opel': [
    FieldOption('astra', 'Astra'),
    FieldOption('corsa', 'Corsa'),
    FieldOption('mokka', 'Mokka'),
    FieldOption('crossland', 'Crossland'),
    FieldOption('grandland', 'Grandland'),
  ],
  'peugeot': [
    FieldOption('208', '208'),
    FieldOption('308', '308'),
    FieldOption('2008', '2008'),
    FieldOption('3008', '3008'),
    FieldOption('508', '508'),
  ],
  'porsche': [
    FieldOption('911', '911'),
    FieldOption('cayenne', 'Cayenne'),
    FieldOption('macan', 'Macan'),
    FieldOption('panamera', 'Panamera'),
    FieldOption('taycan', 'Taycan'),
  ],
  'renault': [
    FieldOption('clio', 'Clio'),
    FieldOption('megane', 'Megane'),
    FieldOption('duster', 'Duster'),
    FieldOption('kadjar', 'Kadjar'),
    FieldOption('symbol', 'Symbol'),
  ],
  'seat': [
    FieldOption('ibiza', 'Ibiza'),
    FieldOption('leon', 'Leon'),
    FieldOption('arona', 'Arona'),
    FieldOption('ateca', 'Ateca'),
    FieldOption('tarraco', 'Tarraco'),
  ],
  'skoda': [
    FieldOption('fabia', 'Fabia'),
    FieldOption('octavia', 'Octavia'),
    FieldOption('karoq', 'Karoq'),
    FieldOption('kodiaq', 'Kodiaq'),
    FieldOption('superb', 'Superb'),
  ],
  'subaru': [
    FieldOption('forester', 'Forester'),
    FieldOption('outback', 'Outback'),
    FieldOption('xv', 'XV'),
    FieldOption('impreza', 'Impreza'),
    FieldOption('legacy', 'Legacy'),
  ],
  'tesla': [
    FieldOption('model_3', 'Model 3'),
    FieldOption('model_y', 'Model Y'),
    FieldOption('model_s', 'Model S'),
    FieldOption('model_x', 'Model X'),
    FieldOption('cybertruck', 'Cybertruck'),
  ],
  'togg': [
    FieldOption('t10x', 'T10X'),
    FieldOption('t10f', 'T10F'),
  ],
  'toyota': [
    FieldOption('corolla', 'Corolla'),
    FieldOption('yaris', 'Yaris'),
    FieldOption('yaris_cross', 'Yaris Cross'),
    FieldOption('rav4', 'RAV4'),
    FieldOption('c_hr', 'C-HR'),
  ],
  'volkswagen': [
    FieldOption('golf', 'Golf'),
    FieldOption('passat', 'Passat'),
    FieldOption('polo', 'Polo'),
    FieldOption('tiguan', 'Tiguan'),
    FieldOption('t_roc', 'T-Roc'),
  ],
  'volvo': [
    FieldOption('xc40', 'XC40'),
    FieldOption('xc60', 'XC60'),
    FieldOption('xc90', 'XC90'),
    FieldOption('s60', 'S60'),
    FieldOption('v60', 'V60'),
  ],
};

const _modellerElektrikli = <String, List<FieldOption>>{
  'tesla': [
    FieldOption('model_3', 'Model 3'),
    FieldOption('model_y', 'Model Y'),
    FieldOption('model_s', 'Model S'),
    FieldOption('model_x', 'Model X'),
    FieldOption('cybertruck', 'Cybertruck'),
  ],
  'togg': [
    FieldOption('t10x', 'T10X'),
    FieldOption('t10f', 'T10F'),
  ],
  'bmw': [
    FieldOption('i4', 'i4'),
    FieldOption('ix', 'iX'),
    FieldOption('ix1', 'iX1'),
    FieldOption('i5', 'i5'),
    FieldOption('i3', 'i3'),
  ],
  'audi': [
    FieldOption('q4_etron', 'Q4 e-tron'),
    FieldOption('etron_gt', 'e-tron GT'),
    FieldOption('q8_etron', 'Q8 e-tron'),
    FieldOption('a6_etron', 'A6 e-tron'),
    FieldOption('q6_etron', 'Q6 e-tron'),
  ],
  'hyundai': [
    FieldOption('ioniq5', 'IONIQ 5'),
    FieldOption('ioniq6', 'IONIQ 6'),
    FieldOption('kona_electric', 'Kona Electric'),
    FieldOption('tucson_phev', 'Tucson PHEV'),
    FieldOption('santa_fe_phev', 'Santa Fe PHEV'),
  ],
  'kia': [
    FieldOption('ev6', 'EV6'),
    FieldOption('ev9', 'EV9'),
    FieldOption('niro_ev', 'Niro EV'),
    FieldOption('sportage_phev', 'Sportage PHEV'),
    FieldOption('ev3', 'EV3'),
  ],
  'volkswagen': [
    FieldOption('id4', 'ID.4'),
    FieldOption('id3', 'ID.3'),
    FieldOption('id7', 'ID.7'),
    FieldOption('id5', 'ID.5'),
    FieldOption('id_buzz', 'ID. Buzz'),
  ],
  'nissan': [
    FieldOption('leaf', 'Leaf'),
    FieldOption('ariya', 'Ariya'),
    FieldOption('leaf_eplus', 'Leaf e+'),
    FieldOption('townstar_ev', 'Townstar EV'),
    FieldOption('qashqai_epower', 'Qashqai e-POWER'),
  ],
  'renault': [
    FieldOption('megane_etech', 'Megane E-Tech'),
    FieldOption('zoe', 'Zoe'),
    FieldOption('twingo_electric', 'Twingo Electric'),
    FieldOption('scenic_etech', 'Scenic E-Tech'),
    FieldOption('5_etech', '5 E-Tech'),
  ],
  'porsche': [
    FieldOption('taycan', 'Taycan'),
    FieldOption('taycan_st', 'Taycan Sport Turismo'),
    FieldOption('taycan_ct', 'Taycan Cross Turismo'),
    FieldOption('cayenne_e_hybrid', 'Cayenne E-Hybrid'),
    FieldOption('panamera_e_hybrid', 'Panamera E-Hybrid'),
  ],
  'mercedes': [
    FieldOption('eqa', 'EQA'),
    FieldOption('eqb', 'EQB'),
    FieldOption('eqc', 'EQC'),
    FieldOption('eqs', 'EQS'),
    FieldOption('eqe', 'EQE'),
  ],
  'peugeot': [
    FieldOption('e208', 'e-208'),
    FieldOption('e2008', 'e-2008'),
    FieldOption('e308', 'e-308'),
    FieldOption('e3008', 'e-3008'),
    FieldOption('e_expert', 'e-Expert'),
  ],
};

const _modellerMoto = <String, List<FieldOption>>{
  'honda': [
    FieldOption('cb650r', 'CB650R'),
    FieldOption('cbr600rr', 'CBR600RR'),
    FieldOption('cb500f', 'CB500F'),
    FieldOption('africa_twin', 'Africa Twin'),
    FieldOption('cb125r', 'CB125R'),
  ],
  'yamaha': [
    FieldOption('mt_07', 'MT-07'),
    FieldOption('yzf_r1', 'YZF-R1'),
    FieldOption('yzf_r3', 'YZF-R3'),
    FieldOption('mt_09', 'MT-09'),
    FieldOption('tracer_9', 'Tracer 9'),
  ],
  'kawasaki': [
    FieldOption('z900', 'Z900'),
    FieldOption('ninja_400', 'Ninja 400'),
    FieldOption('z650', 'Z650'),
    FieldOption('versys_650', 'Versys 650'),
    FieldOption('ninja_zx10r', 'Ninja ZX-10R'),
  ],
  'suzuki': [
    FieldOption('gsx_r750', 'GSX-R750'),
    FieldOption('vstrom_650', 'V-Strom 650'),
    FieldOption('sv650', 'SV650'),
    FieldOption('gsx_s750', 'GSX-S750'),
    FieldOption('burgman_400', 'Burgman 400'),
  ],
  'bmw': [
    FieldOption('r1250gs', 'R 1250 GS'),
    FieldOption('s1000rr', 'S 1000 RR'),
    FieldOption('f800gs', 'F 800 GS'),
    FieldOption('r_ninet', 'R nineT'),
    FieldOption('s1000xr', 'S 1000 XR'),
  ],
  'ducati': [
    FieldOption('panigale_v4', 'Panigale V4'),
    FieldOption('monster', 'Monster'),
    FieldOption('streetfighter_v4', 'Streetfighter V4'),
    FieldOption('multistrada_v4', 'Multistrada V4'),
    FieldOption('supersport_950', 'SuperSport 950'),
  ],
  'harley': [
    FieldOption('sportster_s', 'Sportster S'),
    FieldOption('iron_883', 'Iron 883'),
    FieldOption('fat_boy', 'Fat Boy'),
    FieldOption('road_king', 'Road King'),
    FieldOption('pan_america', 'Pan America 1250'),
  ],
  'royal_enfield': [
    FieldOption('himalayan', 'Himalayan'),
    FieldOption('meteor_350', 'Meteor 350'),
    FieldOption('classic_350', 'Classic 350'),
    FieldOption('interceptor_650', 'Interceptor 650'),
    FieldOption('hunter_350', 'Hunter 350'),
  ],
  'ktm': [
    FieldOption('duke_390', 'Duke 390'),
    FieldOption('adventure_890', 'Adventure 890'),
    FieldOption('duke_790', 'Duke 790'),
    FieldOption('rc_390', 'RC 390'),
    FieldOption('super_duke_r', '1290 Super Duke R'),
  ],
  'triumph': [
    FieldOption('bonneville_t120', 'Bonneville T120'),
    FieldOption('tiger_900', 'Tiger 900'),
    FieldOption('trident_660', 'Trident 660'),
    FieldOption('street_twin', 'Street Twin'),
    FieldOption('tiger_1200', 'Tiger 1200'),
  ],
  'aprilia': [
    FieldOption('rs_660', 'RS 660'),
    FieldOption('tuono_660', 'Tuono 660'),
    FieldOption('rsv4', 'RSV4'),
    FieldOption('dorsoduro_900', 'Dorsoduro 900'),
    FieldOption('sr_gt', 'SR GT'),
  ],
};

const _modellerKamyon = <String, List<FieldOption>>{
  'ford': [
    FieldOption('transit_custom', 'Transit Custom'),
    FieldOption('transit', 'Transit'),
    FieldOption('transit_connect', 'Transit Connect'),
    FieldOption('transit_courier', 'Transit Courier'),
    FieldOption('tourneo', 'Tourneo'),
  ],
  'fiat': [
    FieldOption('fiorino', 'Fiorino'),
    FieldOption('doblo', 'Doblò'),
    FieldOption('ducato', 'Ducato'),
    FieldOption('scudo', 'Scudo'),
    FieldOption('talento', 'Talento'),
  ],
  'volkswagen': [
    FieldOption('caddy', 'Caddy'),
    FieldOption('transporter', 'Transporter'),
    FieldOption('crafter', 'Crafter'),
    FieldOption('multivan', 'Multivan'),
    FieldOption('california', 'California'),
  ],
  'mercedes': [
    FieldOption('sprinter', 'Sprinter'),
    FieldOption('vito', 'Vito'),
    FieldOption('viano', 'Viano'),
    FieldOption('v_klasse', 'V-Klasse'),
    FieldOption('citan', 'Citan'),
  ],
  'renault': [
    FieldOption('master', 'Master'),
    FieldOption('trafic', 'Trafic'),
    FieldOption('kangoo', 'Kangoo'),
    FieldOption('express', 'Express'),
    FieldOption('rapid', 'Rapid'),
  ],
  'opel': [
    FieldOption('vivaro', 'Vivaro'),
    FieldOption('movano', 'Movano'),
    FieldOption('combo', 'Combo'),
    FieldOption('zafira_life', 'Zafira Life'),
    FieldOption('crossland_cargo', 'Crossland Cargo'),
  ],
  'peugeot': [
    FieldOption('expert', 'Expert'),
    FieldOption('boxer', 'Boxer'),
    FieldOption('partner', 'Partner'),
    FieldOption('traveller', 'Traveller'),
    FieldOption('e_expert', 'e-Expert'),
  ],
  'isuzu': [
    FieldOption('d_max', 'D-Max'),
    FieldOption('n_series', 'N-Series'),
    FieldOption('f_series', 'F-Series'),
    FieldOption('mu_x', 'MU-X'),
    FieldOption('elf', 'Elf'),
  ],
  'iveco': [
    FieldOption('daily', 'Daily'),
    FieldOption('eurocargo', 'Eurocargo'),
    FieldOption('stralis', 'Stralis'),
    FieldOption('s_way', 'S-Way'),
    FieldOption('hi_way', 'Hi-Way'),
  ],
  'man': [
    FieldOption('tge', 'TGE'),
    FieldOption('tgl', 'TGL'),
    FieldOption('tgm', 'TGM'),
    FieldOption('tgs', 'TGS'),
    FieldOption('tgx', 'TGX'),
  ],
  'daf': [
    FieldOption('xf', 'XF'),
    FieldOption('xg', 'XG'),
    FieldOption('cf', 'CF'),
    FieldOption('lf', 'LF'),
    FieldOption('xg_plus', 'XG+'),
  ],
  'volvo': [
    FieldOption('fh', 'FH'),
    FieldOption('fm', 'FM'),
    FieldOption('fmx', 'FMX'),
    FieldOption('fl', 'FL'),
    FieldOption('fe', 'FE'),
  ],
  'scania': [
    FieldOption('r_series', 'R Serisi'),
    FieldOption('s_series', 'S Serisi'),
    FieldOption('p_series', 'P Serisi'),
    FieldOption('g_series', 'G Serisi'),
    FieldOption('l_series', 'L Serisi'),
  ],
};

const _modellerTraktor = <String, List<FieldOption>>{
  'new_holland': [
    FieldOption('t5', 'T5'),
    FieldOption('t6', 'T6'),
    FieldOption('t7', 'T7'),
    FieldOption('tk4', 'TK4'),
    FieldOption('td5', 'TD5'),
  ],
  'john_deere': [
    FieldOption('5075e', '5075E'),
    FieldOption('5090r', '5090R'),
    FieldOption('6110r', '6110R'),
    FieldOption('6130r', '6130R'),
    FieldOption('7r', '7R'),
  ],
  'massey_ferguson': [
    FieldOption('mf4700', '4700 Serisi'),
    FieldOption('mf5700', '5700 Serisi'),
    FieldOption('mf6700', '6700 Serisi'),
    FieldOption('mf7700', '7700 Serisi'),
    FieldOption('mf8700', '8700 Serisi'),
  ],
  'kubota': [
    FieldOption('b_series', 'B Serisi'),
    FieldOption('l_series', 'L Serisi'),
    FieldOption('m_series', 'M Serisi'),
    FieldOption('mx_series', 'MX Serisi'),
    FieldOption('st_series', 'ST Serisi'),
  ],
  'fendt': [
    FieldOption('200_vario', '200 Vario'),
    FieldOption('300_vario', '300 Vario'),
    FieldOption('500_vario', '500 Vario'),
    FieldOption('700_vario', '700 Vario'),
    FieldOption('900_vario', '900 Vario'),
  ],
  'case': [
    FieldOption('farmall_a', 'Farmall A'),
    FieldOption('farmall_c', 'Farmall C'),
    FieldOption('maxxum', 'Maxxum'),
    FieldOption('puma', 'Puma'),
    FieldOption('optum', 'Optum'),
  ],
  'tumosan': [
    FieldOption('60hp', '60 HP'),
    FieldOption('70hp', '70 HP'),
    FieldOption('80hp', '80 HP'),
    FieldOption('90hp', '90 HP'),
    FieldOption('100hp', '100 HP'),
  ],
};

const _modellerLaptop = <String, List<FieldOption>>{
  'apple': [
    FieldOption('macbook_air_m2', 'MacBook Air M2'),
    FieldOption('macbook_air_m3', 'MacBook Air M3'),
    FieldOption('macbook_pro_14_m3', 'MacBook Pro 14" M3'),
    FieldOption('macbook_pro_16_m3', 'MacBook Pro 16" M3'),
    FieldOption('macbook_air_15_m2', 'MacBook Air 15" M2'),
  ],
  'asus': [
    FieldOption('zenbook_14', 'ZenBook 14 OLED'),
    FieldOption('rog_strix_g15', 'ROG Strix G15'),
    FieldOption('vivobook_15', 'VivoBook 15'),
    FieldOption('tuf_gaming_a15', 'TUF Gaming A15'),
    FieldOption('proart_studiobook', 'ProArt Studiobook'),
  ],
  'lenovo': [
    FieldOption('thinkpad_e15', 'ThinkPad E15'),
    FieldOption('ideapad_5', 'IdeaPad 5'),
    FieldOption('legion_5', 'Legion 5'),
    FieldOption('yoga_9i', 'Yoga 9i'),
    FieldOption('thinkpad_x1_carbon', 'ThinkPad X1 Carbon'),
  ],
  'dell': [
    FieldOption('xps_13', 'XPS 13'),
    FieldOption('xps_15', 'XPS 15'),
    FieldOption('inspiron_15', 'Inspiron 15'),
    FieldOption('latitude_5440', 'Latitude 5440'),
    FieldOption('g15_gaming', 'G15 Gaming'),
  ],
  'hp': [
    FieldOption('pavilion_15', 'Pavilion 15'),
    FieldOption('elitebook_840', 'EliteBook 840'),
    FieldOption('victus_16', 'Victus 16'),
    FieldOption('omen_16', 'Omen 16'),
    FieldOption('probook_450', 'ProBook 450'),
  ],
  'msi': [
    FieldOption('stealth_15', 'Stealth 15'),
    FieldOption('creator_m16', 'Creator M16'),
    FieldOption('katana_15', 'Katana 15'),
    FieldOption('gf63_thin', 'GF63 Thin'),
    FieldOption('stealth_16', 'Stealth 16'),
  ],
  'acer': [
    FieldOption('swift_3', 'Swift 3'),
    FieldOption('predator_helios', 'Predator Helios 300'),
    FieldOption('aspire_5', 'Aspire 5'),
    FieldOption('nitro_5', 'Nitro 5'),
    FieldOption('swift_x', 'Swift X'),
  ],
  'toshiba': [
    FieldOption('satellite_pro', 'Satellite Pro'),
    FieldOption('tecra_a50', 'Tecra A50'),
    FieldOption('portege_x30', 'Portégé X30'),
    FieldOption('dynabook_e10', 'Dynabook E10'),
    FieldOption('dynabook_cs50', 'Dynabook CS50'),
  ],
  'samsung': [
    FieldOption('galaxy_book3', 'Galaxy Book3'),
    FieldOption('galaxy_book3_pro', 'Galaxy Book3 Pro'),
    FieldOption('galaxy_book3_ultra', 'Galaxy Book3 Ultra'),
    FieldOption('galaxy_book3_360', 'Galaxy Book3 360'),
    FieldOption('galaxy_book2_pro', 'Galaxy Book2 Pro'),
  ],
  'huawei': [
    FieldOption('matebook_d15', 'MateBook D15'),
    FieldOption('matebook_14', 'MateBook 14'),
    FieldOption('matebook_x_pro', 'MateBook X Pro'),
    FieldOption('matebook_d14', 'MateBook D14'),
    FieldOption('matebook_e', 'MateBook E'),
  ],
};

const _modellerTablet = <String, List<FieldOption>>{
  'apple': [
    FieldOption('ipad_air_m1', 'iPad Air M1'),
    FieldOption('ipad_pro_11_m4', 'iPad Pro 11" M4'),
    FieldOption('ipad_10', 'iPad 10. Nesil'),
    FieldOption('ipad_mini_6', 'iPad Mini 6'),
    FieldOption('ipad_pro_13_m4', 'iPad Pro 13" M4'),
  ],
  'samsung': [
    FieldOption('tab_s9', 'Galaxy Tab S9'),
    FieldOption('tab_a8', 'Galaxy Tab A8'),
    FieldOption('tab_s8_plus', 'Galaxy Tab S8+'),
    FieldOption('tab_s9_fe', 'Galaxy Tab S9 FE'),
    FieldOption('tab_a9_plus', 'Galaxy Tab A9+'),
  ],
  'xiaomi': [
    FieldOption('pad_6', 'Pad 6'),
    FieldOption('redmi_pad_se', 'Redmi Pad SE'),
    FieldOption('pad_6_pro', 'Pad 6 Pro'),
    FieldOption('redmi_pad_2', 'Redmi Pad 2'),
    FieldOption('pad_5', 'Pad 5'),
  ],
  'huawei': [
    FieldOption('matepad_11', 'MatePad 11'),
    FieldOption('matepad_pro_13', 'MatePad Pro 13.2"'),
    FieldOption('matepad_t10s', 'MatePad T10s'),
    FieldOption('matepad_se', 'MatePad SE'),
    FieldOption('matepad_10_4', 'MatePad 10.4'),
  ],
  'oneplus': [
    FieldOption('pad', 'OnePlus Pad'),
    FieldOption('pad_go', 'OnePlus Pad Go'),
    FieldOption('pad_2', 'OnePlus Pad 2'),
    FieldOption('pad_pro', 'OnePlus Pad Pro'),
    FieldOption('tab_r16', 'Tab R16'),
  ],
};

const _modellerSaat = <String, List<FieldOption>>{
  'rolex': [
    FieldOption('submariner', 'Submariner'),
    FieldOption('datejust', 'Datejust'),
    FieldOption('day_date', 'Day-Date'),
    FieldOption('gmt_master_ii', 'GMT-Master II'),
    FieldOption('daytona', 'Daytona'),
  ],
  'omega': [
    FieldOption('seamaster', 'Seamaster'),
    FieldOption('speedmaster', 'Speedmaster'),
    FieldOption('constellation', 'Constellation'),
    FieldOption('de_ville', 'De Ville'),
    FieldOption('aqua_terra', 'Aqua Terra'),
  ],
  'seiko': [
    FieldOption('presage', 'Presage'),
    FieldOption('prospex', 'Prospex'),
    FieldOption('5_sports', '5 Sports'),
    FieldOption('astron', 'Astron'),
    FieldOption('alpinist', 'Alpinist'),
  ],
  'casio': [
    FieldOption('g_shock', 'G-Shock'),
    FieldOption('edifice', 'Edifice'),
    FieldOption('pro_trek', 'Pro Trek'),
    FieldOption('wave_ceptor', 'Wave Ceptor'),
    FieldOption('baby_g', 'Baby-G'),
  ],
  'tissot': [
    FieldOption('prx', 'PRX'),
    FieldOption('t_race', 'T-Race'),
    FieldOption('seastar', 'Seastar'),
    FieldOption('le_locle', 'Le Locle'),
    FieldOption('chemin_tourelles', 'Chemin des Tourelles'),
  ],
  'tag_heuer': [
    FieldOption('carrera', 'Carrera'),
    FieldOption('monaco', 'Monaco'),
    FieldOption('aquaracer', 'Aquaracer'),
    FieldOption('formula_1', 'Formula 1'),
    FieldOption('link', 'Link'),
  ],
  'fossil': [
    FieldOption('minimalist', 'Minimalist'),
    FieldOption('carlyle', 'Carlyle'),
    FieldOption('neutra', 'Neutra'),
    FieldOption('fenmore', 'Fenmore'),
    FieldOption('gen_6', 'Gen 6'),
  ],
  'swatch': [
    FieldOption('big_bold', 'Big Bold'),
    FieldOption('sistem51', 'Sistem51'),
    FieldOption('skin', 'Skin'),
    FieldOption('irony', 'Irony'),
    FieldOption('gent', 'Gent'),
  ],
};

const _modellerBisiklet = <String, List<FieldOption>>{
  'giant': [
    FieldOption('contend', 'Contend'),
    FieldOption('defy', 'Defy'),
    FieldOption('tcx', 'TCX'),
    FieldOption('anthem', 'Anthem'),
    FieldOption('trance', 'Trance'),
  ],
  'trek': [
    FieldOption('fx', 'FX'),
    FieldOption('marlin', 'Marlin'),
    FieldOption('domane', 'Domane'),
    FieldOption('emonda', 'Émonda'),
    FieldOption('checkpoint', 'Checkpoint'),
  ],
  'specialized': [
    FieldOption('allez', 'Allez'),
    FieldOption('diverge', 'Diverge'),
    FieldOption('stumpjumper', 'Stumpjumper'),
    FieldOption('roubaix', 'Roubaix'),
    FieldOption('rockhopper', 'Rockhopper'),
  ],
  'bianchi': [
    FieldOption('c_sport', 'C-Sport'),
    FieldOption('sprint', 'Sprint'),
    FieldOption('oltre_xr4', 'Oltre XR4'),
    FieldOption('infinito', 'Infinito'),
    FieldOption('impulso', 'Impulso'),
  ],
  'scott': [
    FieldOption('speedster', 'Speedster'),
    FieldOption('sub_cross', 'Sub Cross'),
    FieldOption('aspect', 'Aspect'),
    FieldOption('contessa', 'Contessa'),
    FieldOption('scale', 'Scale'),
  ],
  'merida': [
    FieldOption('big_nine', 'Big Nine'),
    FieldOption('one_twenty', 'One-Twenty'),
    FieldOption('scultura', 'Scultura'),
    FieldOption('speeder', 'Speeder'),
    FieldOption('reacto', 'Reacto'),
  ],
  'cannondale': [
    FieldOption('quick', 'Quick'),
    FieldOption('trail', 'Trail'),
    FieldOption('topstone', 'Topstone'),
    FieldOption('supersix_evo', 'SuperSix EVO'),
    FieldOption('synapse', 'Synapse'),
  ],
};

// ── Subcategory definitions ───────────────────────────────────────────────────

/// (key, label) pairs per main category key.
const Map<String, List<(String, String)>> kSubcategories = {
  'vehicles': [
    ('automobile', 'Otomobil'),
    ('motorcycle', 'Motosiklet'),
    ('electric_vehicle', 'Elektrikli Araç'),
    ('van_minibus', 'Kamyonet & Minibüs'),
    ('truck', 'Kamyon & Tır'),
    ('tractor', 'Traktör'),
    ('boat', 'Tekne & Su Aracı'),
    ('caravan', 'Karavan'),
    ('spare_parts', 'Yedek Parça'),
  ],
  'electronics': [
    ('mobile_phone', 'Cep Telefonu'),
    ('laptop', 'Bilgisayar & Laptop'),
    ('tablet', 'Tablet'),
    ('tv_monitor', 'TV & Monitör'),
    ('camera', 'Kamera'),
    ('audio_system', 'Ses Sistemi'),
    ('smartwatch', 'Akıllı Saat & Bileklik'),
    ('gaming_console', 'Oyun Konsol'),
    ('other_electronics', 'Diğer Elektronik'),
  ],
  'real_estate': [
    ('apartment', 'Daire'),
    ('house_villa', 'Müstakil Ev & Villa'),
    ('land', 'Arsa'),
    ('field_garden', 'Tarla & Bahçe'),
    ('office', 'İş Yeri & Ofis'),
    ('warehouse', 'Depo & Fabrika'),
    ('building', 'Bina'),
  ],
  'fashion': [
    ('womens_clothing', 'Kadın Giyim'),
    ('mens_clothing', 'Erkek Giyim'),
    ('kids_clothing', 'Çocuk Giyim'),
    ('shoes', 'Ayakkabı'),
    ('bag', 'Çanta'),
    ('jewelry', 'Takı & Mücevher'),
    ('watch', 'Saat'),
    ('accessories', 'Şapka, Kemer & Aksesuar'),
  ],
  'home': [
    ('furniture', 'Mobilya'),
    ('kitchen_equipment', 'Mutfak Gereçleri'),
    ('cleaning_equipment', 'Temizlik Ekipmanı'),
    ('home_textile', 'Ev Tekstili'),
    ('lighting', 'Aydınlatma'),
    ('garden_outdoor', 'Bahçe & Dış Mekan'),
    ('antique', 'Antika & Koleksiyon'),
  ],
  'sports': [
    ('bicycle', 'Bisiklet'),
    ('fitness_equipment', 'Spor Aleti & Fitness'),
    ('outdoor_camping', 'Outdoor & Kamp'),
    ('team_sports', 'Top & Takım Sporları'),
    ('outdoor_sports', 'Doğa Sporları'),
    ('other_sports', 'Diğer Spor'),
  ],
  'books': [
    ('fiction', 'Roman & Hikaye'),
    ('sci_fi', 'Bilim Kurgu'),
    ('self_development', 'Kişisel Gelişim'),
    ('kids_books', 'Çocuk Kitapları'),
    ('school_books', 'Ders & Okul'),
    ('arts_books', 'Müzik & Sanat'),
    ('magazine', 'Koleksiyon & Dergi'),
  ],
  'other': [
    ('pet', 'Evcil Hayvan'),
    ('baby_toys', 'Bebek & Oyuncak'),
    ('musical_instrument', 'Müzik Aleti'),
    ('photo_video', 'Fotoğraf & Video Ekipmanı'),
    ('food_agriculture', 'Yiyecek & Tarım Ürünleri'),
    ('misc', 'Diğer'),
  ],
};

// ── Extra field definitions per subcategory ───────────────────────────────────

const Map<String, List<ExtraFieldDef>> kSubcategoryFields = {
  // ── Vasıta ────────────────────────────────────────────────────────────────
  'automobile': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaArac),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerArac),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'fuel_type', labelKey: 'extraField_fuel_type', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'transmission', labelKey: 'extraField_transmission', type: ExtraFieldType.dropdown, options: _vites),
    ExtraFieldDef(key: 'body_type', labelKey: 'extraField_body_type', type: ExtraFieldType.dropdown, options: _kasaTipi),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'motorcycle': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaMoto),
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _motoTip),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerMoto),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'engine_cc', labelKey: 'extraField_engine_cc', type: ExtraFieldType.number, optional: true, unit: 'cc'),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'electric_vehicle': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaElektrikli),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerElektrikli),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'range_km', labelKey: 'extraField_menzil', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'van_minibus': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaKamyon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerKamyon),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'fuel_type', labelKey: 'extraField_fuel_type', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'transmission', labelKey: 'extraField_transmission', type: ExtraFieldType.dropdown, options: _vitesManuelDefault),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'truck': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaKamyon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerKamyon),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'fuel_type', labelKey: 'extraField_fuel_type', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'transmission', labelKey: 'extraField_transmission', type: ExtraFieldType.dropdown, options: _vitesManuelDefault),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'tractor': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaTaktor),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerTraktor),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'working_hours', labelKey: 'extraField_working_hours', type: ExtraFieldType.number, optional: true, unit: 'saat'),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'boat': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _tekneTip),
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'length', labelKey: 'extraField_length', type: ExtraFieldType.text, unit: 'm'),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown, optional: true),
    ExtraFieldDef(key: 'fuel_type', labelKey: 'extraField_fuel_type', type: ExtraFieldType.dropdown, options: _tekneYakit, optional: true),
  ],
  'caravan': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.dropdown, optional: true),
    ExtraFieldDef(key: 'mileage', labelKey: 'extraField_mileage', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'damage_status', labelKey: 'extraField_damage_status', type: ExtraFieldType.multiselect, options: _hasar, optional: true),
  ],
  'spare_parts': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaArac),
    ExtraFieldDef(key: 'compatible_model', labelKey: 'extraField_compatible_model', optional: true),
    ExtraFieldDef(key: 'part_type', labelKey: 'extraField_part_type', optional: true),
  ],

  // ── Elektronik ────────────────────────────────────────────────────────────
  'mobile_phone': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaTelefon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerTelefon),
    ExtraFieldDef(key: 'storage', labelKey: 'extraField_storage', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram, optional: true),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'laptop': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaBilgisayar),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerLaptop, optional: true),
    ExtraFieldDef(key: 'processor', labelKey: 'extraField_processor', type: ExtraFieldType.dropdown, options: _islemci),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram),
    ExtraFieldDef(key: 'storage', labelKey: 'extraField_storage', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'screen_size', labelKey: 'extraField_screen_size', type: ExtraFieldType.dropdown, options: _ekranBoyutu, optional: true),
  ],
  'tablet': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaTelefon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerTablet),
    ExtraFieldDef(key: 'storage', labelKey: 'extraField_storage', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram, optional: true),
  ],
  'tv_monitor': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'screen_size', labelKey: 'extraField_screen_size', type: ExtraFieldType.dropdown, options: _ekranBoyutu),
  ],
  'camera': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaKamera),
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _kameraTip),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'audio_system': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'smartwatch': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'gaming_console': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _konsolMarka),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, options: _konsolModel),
  ],
  'other_electronics': [],

  // ── Emlak ─────────────────────────────────────────────────────────────────
  'apartment': [
    ExtraFieldDef(key: 'room_count', labelKey: 'extraField_room_count', type: ExtraFieldType.dropdown, options: _odaSayisi),
    ExtraFieldDef(key: 'gross_sqm', labelKey: 'extraField_gross_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_sqm', labelKey: 'extraField_net_sqm', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'building_age', labelKey: 'extraField_building_age', type: ExtraFieldType.dropdown, options: _binaYasi, optional: true),
    ExtraFieldDef(key: 'floor', labelKey: 'extraField_floor', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'floor_count', labelKey: 'extraField_floor_count', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'heating', labelKey: 'extraField_heating', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'furnishing', labelKey: 'extraField_furnishing', type: ExtraFieldType.dropdown, options: _esyaDurumu),
    ExtraFieldDef(key: 'elevator', labelKey: 'extraField_elevator', type: ExtraFieldType.dropdown, options: _varYok, optional: true),
    ExtraFieldDef(key: 'parking', labelKey: 'extraField_parking', type: ExtraFieldType.dropdown, options: _varYok, optional: true),
  ],
  'house_villa': [
    ExtraFieldDef(key: 'room_count', labelKey: 'extraField_room_count', type: ExtraFieldType.dropdown, options: _odaSayisi),
    ExtraFieldDef(key: 'gross_sqm', labelKey: 'extraField_gross_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_sqm', labelKey: 'extraField_net_sqm', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'land_sqm', labelKey: 'extraField_land_sqm', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'building_age', labelKey: 'extraField_building_age', type: ExtraFieldType.dropdown, options: _binaYasi, optional: true),
    ExtraFieldDef(key: 'heating', labelKey: 'extraField_heating', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'furnishing', labelKey: 'extraField_furnishing', type: ExtraFieldType.dropdown, options: _esyaDurumu),
  ],
  'land': [
    ExtraFieldDef(key: 'sqm', labelKey: 'extraField_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'title_deed', labelKey: 'extraField_title_deed', type: ExtraFieldType.dropdown, options: _tapuDurumu),
    ExtraFieldDef(key: 'land_use', labelKey: 'extraField_land_use', type: ExtraFieldType.dropdown, options: _arsaKullanimDurumu, optional: true),
  ],
  'field_garden': [
    ExtraFieldDef(key: 'sqm', labelKey: 'extraField_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'title_deed', labelKey: 'extraField_title_deed', type: ExtraFieldType.dropdown, options: _tapuDurumu),
    ExtraFieldDef(key: 'land_use', labelKey: 'extraField_land_use', type: ExtraFieldType.dropdown, options: _arsaKullanimDurumu, optional: true),
  ],
  'office': [
    ExtraFieldDef(key: 'gross_sqm', labelKey: 'extraField_gross_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_sqm', labelKey: 'extraField_net_sqm', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'floor', labelKey: 'extraField_floor', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'heating', labelKey: 'extraField_heating', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'furnishing', labelKey: 'extraField_furnishing', type: ExtraFieldType.dropdown, options: _esyaDurumu, optional: true),
  ],
  'warehouse': [
    ExtraFieldDef(key: 'gross_sqm', labelKey: 'extraField_gross_sqm', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'floor', labelKey: 'extraField_floor', type: ExtraFieldType.number, optional: true),
  ],
  'building': [
    ExtraFieldDef(key: 'floor_count', labelKey: 'extraField_floor_count', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'unit_count', labelKey: 'extraField_unit_count', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'gross_sqm', labelKey: 'extraField_gross_sqm', type: ExtraFieldType.number, optional: true, unit: 'm²'),
  ],

  // ── Giyim ─────────────────────────────────────────────────────────────────
  'womens_clothing': [
    ExtraFieldDef(key: 'size', labelKey: 'extraField_size', type: ExtraFieldType.dropdown, options: _bedenKadin),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'mens_clothing': [
    ExtraFieldDef(key: 'size', labelKey: 'extraField_size', type: ExtraFieldType.dropdown, options: _bedenKadin),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'kids_clothing': [
    ExtraFieldDef(key: 'size', labelKey: 'extraField_size', type: ExtraFieldType.dropdown, options: _bedenCocuk),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'shoes': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _ayakkabiTip),
    ExtraFieldDef(key: 'shoe_size', labelKey: 'extraField_shoe_size', type: ExtraFieldType.dropdown, options: _numara),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'bag': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
    ExtraFieldDef(key: 'material', labelKey: 'extraField_material', type: ExtraFieldType.dropdown, options: _cantaMalzeme, optional: true),
  ],
  'jewelry': [
    ExtraFieldDef(key: 'material', labelKey: 'extraField_material', type: ExtraFieldType.dropdown, options: _takiMalzeme),
    ExtraFieldDef(key: 'gold_carat', labelKey: 'extraField_gold_carat', type: ExtraFieldType.dropdown, options: _altinAyar, optional: true),
    ExtraFieldDef(key: 'silver_purity', labelKey: 'extraField_silver_purity', type: ExtraFieldType.dropdown, options: _gumusAyar, optional: true),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'watch': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaSaat),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerSaat, optional: true),
    ExtraFieldDef(key: 'gender', labelKey: 'extraField_gender', type: ExtraFieldType.dropdown, options: _saatCinsiyet),
  ],
  'accessories': [
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],

  // ── Ev & Yaşam ────────────────────────────────────────────────────────────
  'furniture': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _mobilyaTip),
    ExtraFieldDef(key: 'material', labelKey: 'extraField_material', type: ExtraFieldType.dropdown, options: _mobilyaMalzeme, optional: true),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'kitchen_equipment': [],
  'cleaning_equipment': [],
  'home_textile': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _evTekstilTip),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'lighting': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _aydinlatmaTip),
    ExtraFieldDef(key: 'color', labelKey: 'extraField_color', type: ExtraFieldType.dropdown, options: _renk),
  ],
  'garden_outdoor': [],
  'antique': [
    ExtraFieldDef(key: 'year', labelKey: 'extraField_year', type: ExtraFieldType.text, optional: true),
  ],

  // ── Spor ──────────────────────────────────────────────────────────────────
  'bicycle': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.dropdown, options: _markaBisiklet),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, dependsOn: 'brand', conditionalOptions: _modellerBisiklet, optional: true),
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _bisikletTip),
    ExtraFieldDef(key: 'wheel_size', labelKey: 'extraField_wheel_size', type: ExtraFieldType.dropdown, options: _jantBoyutu, optional: true),
  ],
  'fitness_equipment': [
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
  ],
  'outdoor_camping': [],
  'team_sports': [
    ExtraFieldDef(key: 'sport_type', labelKey: 'extraField_sport_type', type: ExtraFieldType.dropdown, options: _sporDali),
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
  ],
  'outdoor_sports': [
    ExtraFieldDef(key: 'sport_type', labelKey: 'extraField_sport_type', type: ExtraFieldType.dropdown, options: _sporDali, optional: true),
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
  ],
  'other_sports': [],

  // ── Kitap & Hobi ──────────────────────────────────────────────────────────
  'fiction': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author'),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
  ],
  'sci_fi': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author'),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
  ],
  'self_development': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author'),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
  ],
  'kids_books': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author', optional: true),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
  ],
  'school_books': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author', optional: true),
  ],
  'arts_books': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'author', labelKey: 'extraField_author', optional: true),
  ],
  'magazine': [
    ExtraFieldDef(key: 'book_title', labelKey: 'extraField_book_title'),
    ExtraFieldDef(key: 'publisher', labelKey: 'extraField_publisher', optional: true),
  ],

  // ── Diğer ─────────────────────────────────────────────────────────────────
  'pet': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _evcilHayvanTip),
    ExtraFieldDef(key: 'breed', labelKey: 'extraField_breed', optional: true),
  ],
  'baby_toys': [],
  'musical_instrument': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _muzikAletiTip),
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
  ],
  'photo_video': [
    ExtraFieldDef(key: 'type', labelKey: 'extraField_type', type: ExtraFieldType.dropdown, options: _fotoEkipmanTip),
    ExtraFieldDef(key: 'brand', labelKey: 'extraField_brand', type: ExtraFieldType.text, optional: true),
  ],
  'food_agriculture': [],
  'misc': [],
};
