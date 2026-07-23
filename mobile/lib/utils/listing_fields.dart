// Subcategory definitions and dynamic extra-field specs for the Create Listing form.
//
// Stored values (FieldOption.value) are normalized snake_case strings written
// into extra_fields JSONB. Display labels are Turkish for the pilot; proper
// i18n via ARB keys is a planned follow-up.

// ── Types ─────────────────────────────────────────────────────────────────────

enum ExtraFieldType { text, number, dropdown }

class FieldOption {
  final String value;
  final String label;
  const FieldOption(this.value, this.label);
}

class ExtraFieldDef {
  final String key;
  final String labelKey; // ARB key, e.g. "extraField_marka"
  final ExtraFieldType type;
  final bool optional;
  final List<FieldOption> options; // only for dropdown
  final String? unit; // displayed as suffix hint (e.g. "km", "m²")

  const ExtraFieldDef({
    required this.key,
    required this.labelKey,
    this.type = ExtraFieldType.text,
    this.optional = false,
    this.options = const [],
    this.unit,
  });
}

// ── Shared option lists ───────────────────────────────────────────────────────

const _renk = [
  FieldOption('beyaz', 'Beyaz'),
  FieldOption('gri', 'Gri'),
  FieldOption('siyah', 'Siyah'),
  FieldOption('mavi', 'Mavi'),
  FieldOption('kirmizi', 'Kırmızı'),
  FieldOption('yesil', 'Yeşil'),
  FieldOption('sari', 'Sarı'),
  FieldOption('turuncu', 'Turuncu'),
  FieldOption('mor', 'Mor'),
  FieldOption('pembe', 'Pembe'),
  FieldOption('kahverengi', 'Kahverengi'),
  FieldOption('bej', 'Bej'),
  FieldOption('altin', 'Altın'),
  FieldOption('gumus', 'Gümüş'),
  FieldOption('diger', 'Diğer'),
];

const _yakitTipi = [
  FieldOption('benzin', 'Benzin'),
  FieldOption('dizel', 'Dizel'),
  FieldOption('lpg', 'LPG'),
  FieldOption('hibrit', 'Hibrit'),
  FieldOption('elektrik', 'Elektrik'),
  FieldOption('diger', 'Diğer'),
];

const _vites = [
  FieldOption('manuel', 'Manuel'),
  FieldOption('otomatik', 'Otomatik'),
  FieldOption('yari_otomatik', 'Yarı Otomatik'),
  FieldOption('cvt', 'CVT'),
];

const _vitesManuelDefault = [
  FieldOption('manuel', 'Manuel'),
  FieldOption('otomatik', 'Otomatik'),
  FieldOption('yari_otomatik', 'Yarı Otomatik'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
];

const _motoTip = [
  FieldOption('naked', 'Naked'),
  FieldOption('sport', 'Sport'),
  FieldOption('touring', 'Touring'),
  FieldOption('enduro', 'Enduro'),
  FieldOption('scooter', 'Scooter'),
  FieldOption('chopper', 'Chopper'),
  FieldOption('adventure', 'Adventure'),
  FieldOption('diger', 'Diğer'),
];

const _hasar = [
  FieldOption('hasarsiz', 'Hasarsız'),
  FieldOption('boyali', 'Boyalı'),
  FieldOption('degisen', 'Değişen'),
  FieldOption('hasarli', 'Hasarlı'),
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
  FieldOption('diger', 'Diğer'),
];

const _markaTaktor = [
  FieldOption('new_holland', 'New Holland'),
  FieldOption('john_deere', 'John Deere'),
  FieldOption('massey_ferguson', 'Massey Ferguson'),
  FieldOption('kubota', 'Kubota'),
  FieldOption('fendt', 'Fendt'),
  FieldOption('case', 'Case'),
  FieldOption('tumosan', 'Tümosan'),
  FieldOption('diger', 'Diğer'),
];

const _tekneTip = [
  FieldOption('motor_tekne', 'Motor Tekne'),
  FieldOption('yelkenli', 'Yelkenli'),
  FieldOption('surat_teknesi', 'Sürat Teknesi'),
  FieldOption('kotra', 'Kotra'),
  FieldOption('kanotaj', 'Kanotaj'),
  FieldOption('jet_ski', 'Jet Ski'),
  FieldOption('diger', 'Diğer'),
];

const _tekneYakit = [
  FieldOption('benzin', 'Benzin'),
  FieldOption('dizel', 'Dizel'),
  FieldOption('elektrik', 'Elektrik'),
  FieldOption('yelken', 'Yelken'),
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
];

const _kameraTip = [
  FieldOption('dslr', 'DSLR'),
  FieldOption('mirrorless', 'Mirrorless'),
  FieldOption('kompakt', 'Kompakt'),
  FieldOption('action', 'Action Kamera'),
  FieldOption('video', 'Video Kamera'),
  FieldOption('diger', 'Diğer'),
];

const _markaKamera = [
  FieldOption('canon', 'Canon'),
  FieldOption('nikon', 'Nikon'),
  FieldOption('sony', 'Sony'),
  FieldOption('fujifilm', 'Fujifilm'),
  FieldOption('panasonic', 'Panasonic'),
  FieldOption('olympus', 'Olympus'),
  FieldOption('gopro', 'GoPro'),
  FieldOption('diger', 'Diğer'),
];

const _konsolMarka = [
  FieldOption('playstation', 'PlayStation'),
  FieldOption('xbox', 'Xbox'),
  FieldOption('nintendo', 'Nintendo'),
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
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
  FieldOption('sifir', 'Sıfır (0)'),
  FieldOption('1_5', '1–5 yıl'),
  FieldOption('6_10', '6–10 yıl'),
  FieldOption('11_15', '11–15 yıl'),
  FieldOption('16_20', '16–20 yıl'),
  FieldOption('21_plus', '21 yıl ve üzeri'),
];

const _isitma = [
  FieldOption('kombi', 'Kombi'),
  FieldOption('dogalgaz', 'Doğalgaz (Merkezi)'),
  FieldOption('soba', 'Soba'),
  FieldOption('klima', 'Klima'),
  FieldOption('yerden_isitma', 'Yerden Isıtma'),
  FieldOption('yok', 'Yok'),
];

const _esyaDurumu = [
  FieldOption('esyali', 'Eşyalı'),
  FieldOption('yari_esyali', 'Yarı Eşyalı'),
  FieldOption('bos', 'Boş'),
];

const _varYok = [
  FieldOption('var', 'Var'),
  FieldOption('yok', 'Yok'),
];

const _tapuDurumu = [
  FieldOption('kat_mulkiyeti', 'Kat Mülkiyeti'),
  FieldOption('kat_irtifaki', 'Kat İrtifakı'),
  FieldOption('hisseli', 'Hisseli Tapu'),
  FieldOption('arsa', 'Arsa Tapusu'),
  FieldOption('diger', 'Diğer'),
];

const _arsaKullanimDurumu = [
  FieldOption('konut', 'Konut İmarlı'),
  FieldOption('ticari', 'Ticari İmarlı'),
  FieldOption('tarimsal', 'Tarımsal'),
  FieldOption('sanayi', 'Sanayi'),
  FieldOption('diger', 'Diğer'),
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
  FieldOption('0_3ay', '0–3 Ay'),
  FieldOption('3_6ay', '3–6 Ay'),
  FieldOption('6_12ay', '6–12 Ay'),
  FieldOption('1_2yas', '1–2 Yaş'),
  FieldOption('3_4yas', '3–4 Yaş'),
  FieldOption('5_6yas', '5–6 Yaş'),
  FieldOption('7_8yas', '7–8 Yaş'),
  FieldOption('9_10yas', '9–10 Yaş'),
  FieldOption('11_12yas', '11–12 Yaş'),
  FieldOption('13_14yas', '13–14 Yaş'),
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
  FieldOption('spor', 'Spor / Sneaker'),
  FieldOption('klasik', 'Klasik'),
  FieldOption('bot', 'Bot'),
  FieldOption('sandalet', 'Sandalet'),
  FieldOption('terlik', 'Terlik'),
  FieldOption('topuklu', 'Topuklu'),
  FieldOption('diger', 'Diğer'),
];

const _cantaMalzeme = [
  FieldOption('deri', 'Deri'),
  FieldOption('suni_deri', 'Suni Deri'),
  FieldOption('kumaş', 'Kumaş'),
  FieldOption('kanvas', 'Kanvas'),
  FieldOption('diger', 'Diğer'),
];

const _takiMalzeme = [
  FieldOption('altin', 'Altın'),
  FieldOption('gumus', 'Gümüş'),
  FieldOption('platin', 'Platin'),
  FieldOption('elmas', 'Elmas'),
  FieldOption('dogal_tas', 'Doğal Taş'),
  FieldOption('diger', 'Diğer'),
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
  FieldOption('diger', 'Diğer'),
];

const _saatCinsiyet = [
  FieldOption('erkek', 'Erkek'),
  FieldOption('kadin', 'Kadın'),
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
  FieldOption('diger', 'Diğer'),
];

// Ev & Yaşam
const _mobilyaTip = [
  FieldOption('koltuk', 'Koltuk / Kanepe'),
  FieldOption('yatak', 'Yatak'),
  FieldOption('masa', 'Masa'),
  FieldOption('sandalye', 'Sandalye'),
  FieldOption('dolap', 'Dolap / Gardırop'),
  FieldOption('raf', 'Raf / Kitaplık'),
  FieldOption('sehpa', 'Sehpa'),
  FieldOption('diger', 'Diğer'),
];

const _mobilyaMalzeme = [
  FieldOption('ahsap', 'Ahşap'),
  FieldOption('metal', 'Metal'),
  FieldOption('plastik', 'Plastik'),
  FieldOption('cam', 'Cam'),
  FieldOption('deri', 'Deri'),
  FieldOption('kumas', 'Kumaş'),
  FieldOption('diger', 'Diğer'),
];

const _evTekstilTip = [
  FieldOption('nevresim', 'Nevresim Takımı'),
  FieldOption('yorgan', 'Yorgan'),
  FieldOption('yastik', 'Yastık'),
  FieldOption('havlu', 'Havlu'),
  FieldOption('perde', 'Perde'),
  FieldOption('hali', 'Halı / Kilim'),
  FieldOption('diger', 'Diğer'),
];

const _aydinlatmaTip = [
  FieldOption('avize', 'Avize'),
  FieldOption('abajur', 'Abajur'),
  FieldOption('masa_lambasi', 'Masa Lambası'),
  FieldOption('aplik', 'Aplik'),
  FieldOption('ayak_lambasi', 'Ayak Lambası'),
  FieldOption('diger', 'Diğer'),
];

// Spor
const _bisikletTip = [
  FieldOption('dag', 'Dağ Bisikleti'),
  FieldOption('yol', 'Yol Bisikleti'),
  FieldOption('sehir', 'Şehir Bisikleti'),
  FieldOption('bmx', 'BMX'),
  FieldOption('elektrikli', 'Elektrikli Bisiklet'),
  FieldOption('katlanan', 'Katlanan Bisiklet'),
  FieldOption('diger', 'Diğer'),
];

const _markaBisiklet = [
  FieldOption('giant', 'Giant'),
  FieldOption('trek', 'Trek'),
  FieldOption('specialized', 'Specialized'),
  FieldOption('bianchi', 'Bianchi'),
  FieldOption('scott', 'Scott'),
  FieldOption('merida', 'Merida'),
  FieldOption('cannondale', 'Cannondale'),
  FieldOption('diger', 'Diğer'),
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
  FieldOption('futbol', 'Futbol'),
  FieldOption('basketbol', 'Basketbol'),
  FieldOption('voleybol', 'Voleybol'),
  FieldOption('tenis', 'Tenis'),
  FieldOption('yuzme', 'Yüzme'),
  FieldOption('kosu', 'Koşu'),
  FieldOption('boks', 'Boks / Muay Thai'),
  FieldOption('yoga', 'Yoga / Pilates'),
  FieldOption('doga_sporları', 'Doğa Sporları'),
  FieldOption('diger', 'Diğer'),
];


// Diğer
const _evcilHayvanTip = [
  FieldOption('kopek', 'Köpek'),
  FieldOption('kedi', 'Kedi'),
  FieldOption('kus', 'Kuş'),
  FieldOption('balik', 'Balık'),
  FieldOption('hamster', 'Hamster'),
  FieldOption('tavsan', 'Tavşan'),
  FieldOption('diger', 'Diğer'),
];

const _muzikAletiTip = [
  FieldOption('gitar', 'Gitar'),
  FieldOption('piyano', 'Piyano / Klavye'),
  FieldOption('davul', 'Davul / Perküsyon'),
  FieldOption('keman', 'Keman'),
  FieldOption('saz', 'Saz / Bağlama'),
  FieldOption('flut', 'Flüt'),
  FieldOption('diger', 'Diğer'),
];

const _fotoEkipmanTip = [
  FieldOption('kamera', 'Kamera'),
  FieldOption('lens', 'Lens'),
  FieldOption('tripod', 'Tripod'),
  FieldOption('drone', 'Drone'),
  FieldOption('flas', 'Flaş / Işık'),
  FieldOption('diger', 'Diğer'),
];

// ── Subcategory definitions ───────────────────────────────────────────────────

/// (key, label) pairs per main category key.
const Map<String, List<(String, String)>> kSubcategories = {
  'vasita': [
    ('otomobil', 'Otomobil'),
    ('motosiklet', 'Motosiklet'),
    ('elektrikli_arac', 'Elektrikli Araç'),
    ('kamyonet_minibus', 'Kamyonet & Minibüs'),
    ('kamyon_tir', 'Kamyon & Tır'),
    ('traktor', 'Traktör'),
    ('tekne_su_araci', 'Tekne & Su Aracı'),
    ('karavan', 'Karavan'),
    ('yedek_parca', 'Yedek Parça'),
  ],
  'elektronik': [
    ('telefon', 'Telefon'),
    ('bilgisayar_laptop', 'Bilgisayar & Laptop'),
    ('tablet', 'Tablet'),
    ('tv_monitor', 'TV & Monitör'),
    ('kamera', 'Kamera'),
    ('ses_sistemi', 'Ses Sistemi'),
    ('akilli_saat_bileklik', 'Akıllı Saat & Bileklik'),
    ('oyun_konsol', 'Oyun Konsol'),
    ('diger_elektronik', 'Diğer Elektronik'),
  ],
  'emlak': [
    ('daire', 'Daire'),
    ('mustakil_ev_villa', 'Müstakil Ev & Villa'),
    ('arsa', 'Arsa'),
    ('tarla_bahce', 'Tarla & Bahçe'),
    ('is_yeri_ofis', 'İş Yeri & Ofis'),
    ('depo_fabrika', 'Depo & Fabrika'),
    ('bina', 'Bina'),
  ],
  'giyim': [
    ('kadin_giyim', 'Kadın Giyim'),
    ('erkek_giyim', 'Erkek Giyim'),
    ('cocuk_giyim', 'Çocuk Giyim'),
    ('ayakkabi', 'Ayakkabı'),
    ('canta', 'Çanta'),
    ('taki_mucevher', 'Takı & Mücevher'),
    ('saat_giyim', 'Saat'),
    ('sapka_kemer_aksesuar', 'Şapka, Kemer & Aksesuar'),
  ],
  'ev': [
    ('mobilya', 'Mobilya'),
    ('mutfak_gerecleri', 'Mutfak Gereçleri'),
    ('temizlik_ekipmani', 'Temizlik Ekipmanı'),
    ('ev_tekstil', 'Ev Tekstili'),
    ('aydinlatma', 'Aydınlatma'),
    ('bahce_dis_mekan', 'Bahçe & Dış Mekan'),
    ('antika_koleksiyon', 'Antika & Koleksiyon'),
  ],
  'spor': [
    ('bisiklet', 'Bisiklet'),
    ('spor_aleti_fitness', 'Spor Aleti & Fitness'),
    ('outdoor_kamp', 'Outdoor & Kamp'),
    ('top_takim_sporlari', 'Top & Takım Sporları'),
    ('doga_sporlari', 'Doğa Sporları'),
    ('diger_spor', 'Diğer Spor'),
  ],
  'kitap': [
    ('roman_hikaye', 'Roman & Hikaye'),
    ('bilim_kurgu', 'Bilim Kurgu'),
    ('kisisel_gelisim', 'Kişisel Gelişim'),
    ('cocuk_kitaplari', 'Çocuk Kitapları'),
    ('ders_okul', 'Ders & Okul'),
    ('muzik_sanat_kitap', 'Müzik & Sanat'),
    ('koleksiyon_dergi', 'Koleksiyon & Dergi'),
  ],
  'diger': [
    ('evcil_hayvan', 'Evcil Hayvan'),
    ('bebek_oyuncak', 'Bebek & Oyuncak'),
    ('muzik_aleti', 'Müzik Aleti'),
    ('foto_video_ekipmani', 'Fotoğraf & Video Ekipmanı'),
    ('yiyecek_tarim', 'Yiyecek & Tarım Ürünleri'),
    ('diger_kategori', 'Diğer'),
  ],
};

// ── Extra field definitions per subcategory ───────────────────────────────────

const Map<String, List<ExtraFieldDef>> kSubcategoryFields = {
  // ── Vasıta ────────────────────────────────────────────────────────────────
  'otomobil': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaArac),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'yakit', labelKey: 'extraField_yakit', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'vites', labelKey: 'extraField_vites', type: ExtraFieldType.dropdown, options: _vites),
    ExtraFieldDef(key: 'kasa_tipi', labelKey: 'extraField_kasa_tipi', type: ExtraFieldType.dropdown, options: _kasaTipi),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
    ExtraFieldDef(key: 'hasar', labelKey: 'extraField_hasar', type: ExtraFieldType.dropdown, options: _hasar, optional: true),
  ],
  'motosiklet': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaMoto),
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _motoTip),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'motor_cc', labelKey: 'extraField_motor_cc', type: ExtraFieldType.number, optional: true, unit: 'cc'),
  ],
  'elektrikli_arac': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaElektrikli),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'menzil_km', labelKey: 'extraField_menzil', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'kamyonet_minibus': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaKamyon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'yakit', labelKey: 'extraField_yakit', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'vites', labelKey: 'extraField_vites', type: ExtraFieldType.dropdown, options: _vitesManuelDefault),
  ],
  'kamyon_tir': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaKamyon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'yakit', labelKey: 'extraField_yakit', type: ExtraFieldType.dropdown, options: _yakitTipi),
    ExtraFieldDef(key: 'vites', labelKey: 'extraField_vites', type: ExtraFieldType.dropdown, options: _vitesManuelDefault),
  ],
  'traktor': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaTaktor),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
    ExtraFieldDef(key: 'calisma_saati', labelKey: 'extraField_calisma_saati', type: ExtraFieldType.number, optional: true, unit: 'saat'),
  ],
  'tekne_su_araci': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _tekneTip),
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'uzunluk', labelKey: 'extraField_uzunluk', type: ExtraFieldType.text, unit: 'm'),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'yakit', labelKey: 'extraField_yakit', type: ExtraFieldType.dropdown, options: _tekneYakit, optional: true),
  ],
  'karavan': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'km', labelKey: 'extraField_km', type: ExtraFieldType.number, optional: true, unit: 'km'),
  ],
  'yedek_parca': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaArac),
    ExtraFieldDef(key: 'uyumlu_model', labelKey: 'extraField_uyumlu_model', optional: true),
    ExtraFieldDef(key: 'parca_tipi', labelKey: 'extraField_parca_tipi', optional: true),
  ],

  // ── Elektronik ────────────────────────────────────────────────────────────
  'telefon': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaTelefon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'depolama', labelKey: 'extraField_depolama', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram, optional: true),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'bilgisayar_laptop': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaBilgisayar),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'islemci', labelKey: 'extraField_islemci', type: ExtraFieldType.dropdown, options: _islemci),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram),
    ExtraFieldDef(key: 'depolama', labelKey: 'extraField_depolama', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'ekran_boyutu', labelKey: 'extraField_ekran_boyutu', type: ExtraFieldType.dropdown, options: _ekranBoyutu, optional: true),
  ],
  'tablet': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaTelefon),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model'),
    ExtraFieldDef(key: 'depolama', labelKey: 'extraField_depolama', type: ExtraFieldType.dropdown, options: _depolamaKucuk),
    ExtraFieldDef(key: 'ram', labelKey: 'extraField_ram', type: ExtraFieldType.dropdown, options: _ram, optional: true),
  ],
  'tv_monitor': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'ekran_boyutu', labelKey: 'extraField_ekran_boyutu', type: ExtraFieldType.dropdown, options: _ekranBoyutu),
  ],
  'kamera': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaKamera),
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _kameraTip),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'ses_sistemi': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'akilli_saat_bileklik': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
  ],
  'oyun_konsol': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _konsolMarka),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', type: ExtraFieldType.dropdown, options: _konsolModel),
  ],
  'diger_elektronik': [],

  // ── Emlak ─────────────────────────────────────────────────────────────────
  'daire': [
    ExtraFieldDef(key: 'oda_sayisi', labelKey: 'extraField_oda_sayisi', type: ExtraFieldType.dropdown, options: _odaSayisi),
    ExtraFieldDef(key: 'brut_m2', labelKey: 'extraField_brut_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_m2', labelKey: 'extraField_net_m2', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'bina_yasi', labelKey: 'extraField_bina_yasi', type: ExtraFieldType.dropdown, options: _binaYasi, optional: true),
    ExtraFieldDef(key: 'kat', labelKey: 'extraField_kat', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'kat_sayisi', labelKey: 'extraField_kat_sayisi', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'isitma', labelKey: 'extraField_isitma', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'esya_durumu', labelKey: 'extraField_esya_durumu', type: ExtraFieldType.dropdown, options: _esyaDurumu),
    ExtraFieldDef(key: 'asansor', labelKey: 'extraField_asansor', type: ExtraFieldType.dropdown, options: _varYok, optional: true),
    ExtraFieldDef(key: 'otopark', labelKey: 'extraField_otopark', type: ExtraFieldType.dropdown, options: _varYok, optional: true),
  ],
  'mustakil_ev_villa': [
    ExtraFieldDef(key: 'oda_sayisi', labelKey: 'extraField_oda_sayisi', type: ExtraFieldType.dropdown, options: _odaSayisi),
    ExtraFieldDef(key: 'brut_m2', labelKey: 'extraField_brut_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_m2', labelKey: 'extraField_net_m2', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'arsa_m2', labelKey: 'extraField_arsa_m2', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'bina_yasi', labelKey: 'extraField_bina_yasi', type: ExtraFieldType.dropdown, options: _binaYasi, optional: true),
    ExtraFieldDef(key: 'isitma', labelKey: 'extraField_isitma', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'esya_durumu', labelKey: 'extraField_esya_durumu', type: ExtraFieldType.dropdown, options: _esyaDurumu),
  ],
  'arsa': [
    ExtraFieldDef(key: 'm2', labelKey: 'extraField_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'tapu_durumu', labelKey: 'extraField_tapu_durumu', type: ExtraFieldType.dropdown, options: _tapuDurumu),
    ExtraFieldDef(key: 'kullanim_durumu', labelKey: 'extraField_kullanim_durumu', type: ExtraFieldType.dropdown, options: _arsaKullanimDurumu, optional: true),
  ],
  'tarla_bahce': [
    ExtraFieldDef(key: 'm2', labelKey: 'extraField_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'tapu_durumu', labelKey: 'extraField_tapu_durumu', type: ExtraFieldType.dropdown, options: _tapuDurumu),
    ExtraFieldDef(key: 'kullanim_durumu', labelKey: 'extraField_kullanim_durumu', type: ExtraFieldType.dropdown, options: _arsaKullanimDurumu, optional: true),
  ],
  'is_yeri_ofis': [
    ExtraFieldDef(key: 'brut_m2', labelKey: 'extraField_brut_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'net_m2', labelKey: 'extraField_net_m2', type: ExtraFieldType.number, optional: true, unit: 'm²'),
    ExtraFieldDef(key: 'kat', labelKey: 'extraField_kat', type: ExtraFieldType.number, optional: true),
    ExtraFieldDef(key: 'isitma', labelKey: 'extraField_isitma', type: ExtraFieldType.dropdown, options: _isitma, optional: true),
    ExtraFieldDef(key: 'esya_durumu', labelKey: 'extraField_esya_durumu', type: ExtraFieldType.dropdown, options: _esyaDurumu, optional: true),
  ],
  'depo_fabrika': [
    ExtraFieldDef(key: 'brut_m2', labelKey: 'extraField_brut_m2', type: ExtraFieldType.number, unit: 'm²'),
    ExtraFieldDef(key: 'kat', labelKey: 'extraField_kat', type: ExtraFieldType.number, optional: true),
  ],
  'bina': [
    ExtraFieldDef(key: 'kat_sayisi', labelKey: 'extraField_kat_sayisi', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'daire_sayisi', labelKey: 'extraField_daire_sayisi', type: ExtraFieldType.number),
    ExtraFieldDef(key: 'brut_m2', labelKey: 'extraField_brut_m2', type: ExtraFieldType.number, optional: true, unit: 'm²'),
  ],

  // ── Giyim ─────────────────────────────────────────────────────────────────
  'kadin_giyim': [
    ExtraFieldDef(key: 'beden', labelKey: 'extraField_beden', type: ExtraFieldType.dropdown, options: _bedenKadin),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'erkek_giyim': [
    ExtraFieldDef(key: 'beden', labelKey: 'extraField_beden', type: ExtraFieldType.dropdown, options: _bedenKadin),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'cocuk_giyim': [
    ExtraFieldDef(key: 'beden', labelKey: 'extraField_beden', type: ExtraFieldType.dropdown, options: _bedenCocuk),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'ayakkabi': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _ayakkabiTip),
    ExtraFieldDef(key: 'numara', labelKey: 'extraField_numara', type: ExtraFieldType.dropdown, options: _numara),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'canta': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
    ExtraFieldDef(key: 'malzeme', labelKey: 'extraField_malzeme', type: ExtraFieldType.dropdown, options: _cantaMalzeme, optional: true),
  ],
  'taki_mucevher': [
    ExtraFieldDef(key: 'malzeme', labelKey: 'extraField_malzeme', type: ExtraFieldType.dropdown, options: _takiMalzeme),
    ExtraFieldDef(key: 'altin_ayar', labelKey: 'extraField_altin_ayar', type: ExtraFieldType.dropdown, options: _altinAyar, optional: true),
    ExtraFieldDef(key: 'gumus_ayar', labelKey: 'extraField_gumus_ayar', type: ExtraFieldType.dropdown, options: _gumusAyar, optional: true),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'saat_giyim': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaSaat),
    ExtraFieldDef(key: 'model', labelKey: 'extraField_model', optional: true),
    ExtraFieldDef(key: 'cinsiyet', labelKey: 'extraField_cinsiyet', type: ExtraFieldType.dropdown, options: _saatCinsiyet),
  ],
  'sapka_kemer_aksesuar': [
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],

  // ── Ev & Yaşam ────────────────────────────────────────────────────────────
  'mobilya': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _mobilyaTip),
    ExtraFieldDef(key: 'malzeme', labelKey: 'extraField_malzeme', type: ExtraFieldType.dropdown, options: _mobilyaMalzeme, optional: true),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'mutfak_gerecleri': [],
  'temizlik_ekipmani': [],
  'ev_tekstil': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _evTekstilTip),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'aydinlatma': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _aydinlatmaTip),
    ExtraFieldDef(key: 'renk', labelKey: 'extraField_renk', type: ExtraFieldType.dropdown, options: _renk, optional: true),
  ],
  'bahce_dis_mekan': [],
  'antika_koleksiyon': [
    ExtraFieldDef(key: 'yil', labelKey: 'extraField_yil', type: ExtraFieldType.text, optional: true),
  ],

  // ── Spor ──────────────────────────────────────────────────────────────────
  'bisiklet': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.dropdown, options: _markaBisiklet),
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _bisikletTip),
    ExtraFieldDef(key: 'jant_boyutu', labelKey: 'extraField_jant_boyutu', type: ExtraFieldType.dropdown, options: _jantBoyutu, optional: true),
  ],
  'spor_aleti_fitness': [
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
  ],
  'outdoor_kamp': [],
  'top_takim_sporlari': [
    ExtraFieldDef(key: 'spor_dali', labelKey: 'extraField_spor_dali', type: ExtraFieldType.dropdown, options: _sporDali),
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
  ],
  'doga_sporlari': [
    ExtraFieldDef(key: 'spor_dali', labelKey: 'extraField_spor_dali', type: ExtraFieldType.dropdown, options: _sporDali, optional: true),
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
  ],
  'diger_spor': [],

  // ── Kitap & Hobi ──────────────────────────────────────────────────────────
  'roman_hikaye': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar'),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
  ],
  'bilim_kurgu': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar'),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
  ],
  'kisisel_gelisim': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar'),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
  ],
  'cocuk_kitaplari': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar', optional: true),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
  ],
  'ders_okul': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar', optional: true),
  ],
  'muzik_sanat_kitap': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yazar', labelKey: 'extraField_yazar', optional: true),
  ],
  'koleksiyon_dergi': [
    ExtraFieldDef(key: 'kitap_ismi', labelKey: 'extraField_kitap_ismi'),
    ExtraFieldDef(key: 'yayinevi', labelKey: 'extraField_yayinevi', optional: true),
  ],

  // ── Diğer ─────────────────────────────────────────────────────────────────
  'evcil_hayvan': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _evcilHayvanTip),
    ExtraFieldDef(key: 'irk', labelKey: 'extraField_irk', optional: true),
  ],
  'bebek_oyuncak': [],
  'muzik_aleti': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _muzikAletiTip),
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
  ],
  'foto_video_ekipmani': [
    ExtraFieldDef(key: 'tip', labelKey: 'extraField_tip', type: ExtraFieldType.dropdown, options: _fotoEkipmanTip),
    ExtraFieldDef(key: 'marka', labelKey: 'extraField_marka', type: ExtraFieldType.text, optional: true),
  ],
  'yiyecek_tarim': [],
  'diger_kategori': [],
};
