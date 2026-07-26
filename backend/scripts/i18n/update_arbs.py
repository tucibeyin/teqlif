import os
import sys
import json
import re

script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(script_dir, "..", "..", ".."))
backend_dir = os.path.join(project_root, "backend")
alembic_dir = os.path.join(backend_dir, "alembic", "versions")
mobile_l10n_dir = os.path.join(project_root, "mobile", "lib", "l10n")


def read_arb(lang):
    path = os.path.join(mobile_l10n_dir, f"app_{lang}.arb")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f), path

def write_arb(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

tr_arb, tr_path = read_arb("tr")
en_arb, en_path = read_arb("en")
ar_arb, ar_path = read_arb("ar")
ru_arb, ru_path = read_arb("ru")

print(f"Initial key counts -> TR: {len(tr_arb)}, EN: {len(en_arb)}, AR: {len(ar_arb)}, RU: {len(ru_arb)}")

all_options = {}

# 1. Load from listing_fields.dart
listing_fields_path = os.path.join(project_root, "mobile", "lib", "utils", "listing_fields.dart")
with open(listing_fields_path, "r", encoding="utf-8") as f:
    lf_content = f.read()

for val, lbl in re.findall(r"FieldOption\s*\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]", lf_content):
    all_options[val] = lbl

# 2. Load from zw_category_fields_schema.py using zero-dependency regex
# In zw_category_fields_schema.py, 2-tuples followed by ',' or ']' are options in _TOP_OPTIONS or _COND_OPTIONS lists.
# Dictionary keys are followed by ':' so they will NOT match!
zw_path = os.path.join(alembic_dir, "zw_category_fields_schema.py")
with open(zw_path, "r", encoding="utf-8") as f:
    zw_content = f.read()

for val, lbl in re.findall(r"\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)\s*(?:,|$|\])", zw_content):
    if not val.startswith("subcat_") and not val.startswith("cat_") and not val.startswith("field_") and not val.startswith("extraField_"):
        all_options[val] = lbl

# 3. Load from zx_hasar_multiselect.py (4-tuples)
zx_path = os.path.join(alembic_dir, "zx_hasar_multiselect.py")
if os.path.exists(zx_path):
    with open(zx_path, "r", encoding="utf-8") as f:
        zx_content = f.read()
    for val, lbl in re.findall(r"\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*,\s*[^,]+\s*,\s*(?:\d+|None)\)", zx_content):
        all_options[val] = lbl

# 4. Load from zz_hasar_vasita_all.py (4-tuples)
zz_path = os.path.join(alembic_dir, "zz_hasar_vasita_all.py")
if os.path.exists(zz_path):
    with open(zz_path, "r", encoding="utf-8") as f:
        zz_content = f.read()
    for val, lbl in re.findall(r"\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*,\s*[^,]+\s*,\s*(?:\d+|None)\)", zz_content):
        all_options[val] = lbl

# 5. Load from aad_translations_table.py (_OPT_DATA)
aad_path = os.path.join(alembic_dir, "aad_translations_table.py")
if os.path.exists(aad_path):
    with open(aad_path, "r", encoding="utf-8") as f:
        aad_content = f.read()
    for match in re.finditer(r"'opt_([^']+)':\s*\{\s*'tr':\s*'([^']+)',\s*'en':\s*'([^']+)',\s*'ar':\s*'([^']+)',\s*'ru':\s*'([^']+)'\s*\}", aad_content):
        val, tr_val, en_val, ar_val, ru_val = match.groups()
        all_options[val] = tr_val
        key = f"opt_{val}"
        tr_arb[key] = tr_val
        en_arb[key] = en_val
        ar_arb[key] = ar_val
        ru_arb[key] = ru_val

# Load OPTION_VALUE_MAP from aac_english_keys.py
aac_path = os.path.join(alembic_dir, "aac_english_keys.py")
option_value_map = {}
if os.path.exists(aac_path):
    with open(aac_path, "r", encoding="utf-8") as f:
        aac_code = f.read()
    m = re.search(r"OPTION_VALUE_MAP:\s*dict\[str,\s*str\]\s*=\s*(\{.*?\})\n\n", aac_code, re.DOTALL)
    if m:
        import ast
        try:
            option_value_map = ast.literal_eval(m.group(1))
        except Exception as e:
            print("Error parsing OPTION_VALUE_MAP:", e)

# Explicit English aliases for vehicle damage and other critical terms
ENGLISH_KEY_ALIASES = {
    "boyali": ["painted"],
    "kazali": ["accident", "accidented"],
    "hasar_kayitli": ["damage_record"],
    "agir_hasar_kayitli": ["heavy_damage_record"],
    "hatasiz": ["flawless"],
    "hasarsiz": ["no_damage"],
    "degisen": ["replaced", "repainted"],
    "hasarli": ["damaged", "damaged_old"],
    "sifir": ["new_build", "zero", "new_0"],
    "esyali": ["furnished"],
    "yari_esyali": ["semi_furnished"],
    "bos": ["empty"],
    "kombi": ["combi_boiler"],
    "dogalgaz": ["central_gas"],
    "soba": ["stove"],
    "klima": ["air_conditioning"],
    "yerden_isitma": ["underfloor_heating"],
    "erkek": ["male"],
    "kadin": ["female"],
    "arsa": ["land_title"],
    "konut": ["residential"],
    "ticari": ["commercial"],
    "tarimsal": ["agricultural"],
    "sanayi": ["industrial"],
    "var": ["yes"],
    "yok": ["no"],
}

print(f"Total true unique option values collected: {len(all_options)}")

# Build full set of valid option keys (both Turkish raw keys and English programmatic keys)
valid_opt_keys = set()
for val in all_options.keys():
    valid_opt_keys.add(f"opt_{val}")
    if val in option_value_map:
        valid_opt_keys.add(f"opt_{option_value_map[val]}")
    if val in ENGLISH_KEY_ALIASES:
        for alias in ENGLISH_KEY_ALIASES[val]:
            valid_opt_keys.add(f"opt_{alias}")

static_opts = {"opt_white", "opt_gray", "opt_black", "opt_blue", "opt_red", "opt_green", "opt_yellow", "opt_orange", "opt_purple", "opt_pink", "opt_brown", "opt_beige", "opt_gold", "opt_silver", "opt_gasoline", "opt_diesel", "opt_lpg", "opt_hybrid", "opt_electric", "opt_manual", "opt_automatic", "opt_semi_automatic", "opt_sedan", "opt_hatchback", "opt_suv", "opt_station_wagon", "opt_coupe", "opt_cabriolet", "opt_pickup", "opt_van", "opt_minibus", "opt_painted", "opt_damage_record", "opt_heavy_damage_record", "opt_flawless", "opt_other"}

for arb in [tr_arb, en_arb, ar_arb, ru_arb]:
    keys_to_remove = [k for k in arb.keys() if k.startswith("opt_") and k not in valid_opt_keys and k not in static_opts]
    for k in keys_to_remove:
        del arb[k]

# Comprehensive Turkish -> EN / AR / RU dictionary for option terms
# Note: Global brand names and model codes (BMW, Audi, Giulia, A3, iPhone, numbers, etc.) are NOT in this dict,
# so they will remain identical across all languages as requested ("BMW her dilde BMW dir").
known_en = {
    "1 Serisi": "1 Series", "3 Serisi": "3 Series", "5 Serisi": "5 Series",
    "A Serisi": "A-Class", "C Serisi": "C-Class", "E Serisi": "E-Class",
    "Beyaz": "White", "Gri": "Gray", "Siyah": "Black", "Mavi": "Blue",
    "Kırmızı": "Red", "Yeşil": "Green", "Sarı": "Yellow", "Turuncu": "Orange",
    "Mor": "Purple", "Pembe": "Pink", "Kahverengi": "Brown", "Bej": "Beige",
    "Altın": "Gold", "Gümüş": "Silver", "Diğer": "Other", "Var": "Yes",
    "Yok": "No", "Benzin": "Gasoline", "Dizel": "Diesel", "Hibrit": "Hybrid",
    "Elektrik": "Electric", "Yelken": "Sail", "Manuel": "Manual",
    "Otomatik": "Automatic", "Yarı Otomatik": "Semi-Automatic",
    "Minibüs": "Minibus", "Boyalı": "Painted", "Kazalı": "Accidented",
    "Hasar Kayıtlı": "Damage Record", "Ağır Hasar Kayıtlı": "Heavy Damage Record",
    "Hatasız": "Flawless", "Hasarsız": "No Damage", "Hasarlı": "Damaged",
    "Değişen / Boyalı": "Replaced / Painted", "Değişen": "Replaced",
    "Motor Tekne": "Motorboat", "Yelkenli": "Sailboat", "Sürat Teknesi": "Speedboat",
    "Kotra": "Cutter", "Kanotaj / Kayak": "Canoe / Kayak", "Kompakt": "Compact",
    "Sıfır": "New", "İkinci El": "Used", "Yeni Gibi": "Like New",
    "Yenilenmiş": "Refurbished", "Az Hasarlı": "Minor Damage",
    "Ağır Hasarlı": "Heavy Damage", "Hurda / Parça": "Scrap / Parts",
    "Önden Çekiş": "Front-Wheel Drive", "Arkadan İtiş": "Rear-Wheel Drive",
    "4 Çekiş (4x4)": "Four-Wheel Drive (4x4)", "AWD (Sürekli 4 Çekiş)": "All-Wheel Drive (AWD)",
    "Stüdyo (1+0)": "Studio (1+0)", "Müstakil / Villa": "Detached / Villa",
    "Çiftlik Evi": "Farmhouse", "Köşk / Konak": "Mansion", "Yalı": "Waterfront Residence",
    "İş Hanı": "Office Building", "Plaza Katı": "Plaza Floor", "Komple Bina": "Whole Building",
    "Depo / Antrepo": "Warehouse", "Fabrika": "Factory", "Atölye": "Workshop",
    "Dükkan / Mağaza": "Shop / Store", "Kafe / Restoran": "Cafe / Restaurant",
    "Otel / Butik Otel": "Hotel / Boutique Hotel", "Pansiyon": "Pension",
    "Tatil Köyü": "Holiday Village", "Kamp Alanı": "Campsite",
    "Tarla": "Field", "Arsa (İmarlı)": "Zoned Land", "Zeytinlik": "Olive Grove",
    "Bağ / Bahçe": "Vineyard / Garden", "Sera": "Greenhouse", "Otlak / Mera": "Pasture",
    "Satılık": "For Sale", "Kiralık": "For Rent", "Günlük Kiralık": "Daily Rent",
    "Devren Satılık": "For Transfer Sale", "Devren Kiralık": "For Transfer Rent",
    "Kat Mülkiyeti": "Condominium Ownership", "Kat İrtifakı": "Construction Servitude",
    "Hisseli Tapu": "Shared Deed", "Arsa Tapulu": "Land Deed",
    "Boş": "Vacant", "Kiracılı": "Tenant Occupied", "Mal Sahibi Oturuyor": "Owner Occupied",
    "Kuzey": "North", "Güney": "South", "Doğu": "East", "Batı": "West",
    "Kuzeydoğu": "Northeast", "Kuzeybatı": "Northwest", "Güneydoğu": "Southeast", "Güneybatı": "Southwest",
    "100 Mbps ve altı": "100 Mbps or below", "101 - 500 Mbps": "101 - 500 Mbps",
    "501 - 1000 Mbps": "501 - 1000 Mbps", "1001 Mbps ve üzeri (Wi-Fi 6/6E/7)": "1001 Mbps and above (Wi-Fi 6/6E/7)",
    "Wi-Fi 5 (802.11ac)": "Wi-Fi 5 (802.11ac)", "Wi-Fi 6 / 6E (802.11ax)": "Wi-Fi 6 / 6E (802.11ax)",
    "Wi-Fi 7 (802.11be)": "Wi-Fi 7 (802.11be)", "Mesh Sistem (Çoklu Nokta)": "Mesh System (Multi-node)",
    "Sıfır (Kapalı Kutu)": "Brand New (Sealed)", "Yeni Gibi (Kusursuz)": "Like New (Flawless)",
    "İyi (Hafif Kullanım İzleri)": "Good (Minor Wear)", "Kabul Edilebilir (Belirgin Çizik/İz)": "Acceptable (Visible Wear)",
    "Yenilenmiş (Refurbished)": "Refurbished", "Arızalı / Parça Niyetine": "Faulty / For Parts",
    "Otomobil": "Car", "Motosiklet": "Motorcycle", "Arazi, SUV & Pickup": "Off-road, SUV & Pickup",
    "Ticari Araçlar": "Commercial Vehicles", "Elektrikli Araçlar": "Electric Vehicles",
    "Deniz Araçları": "Marine Vehicles", "Hasarlı Araçlar": "Damaged Vehicles",
    "Daire": "Apartment", "Villa / Müstakil": "Villa / Detached", "Arsa & Tarla": "Land & Field",
    "İş Yeri & Ofis": "Workplace & Office", "Turistik Tesis": "Tourist Facility",
    "Cep Telefonu": "Mobile Phone", "Bilgisayar & Tablet": "Computer & Tablet",
    "TV, Ses & Görüntü": "TV, Audio & Video", "Saat & Giyilebilir Teknoloji": "Watch & Wearable Tech",
    "Oyun & Konsol": "Gaming & Console", "Fotoğraf & Kamera": "Photo & Camera",
    "Ağ & Modem": "Network & Modem", "Ev Aletleri": "Home Appliances",
    "Kişisel Bakım & Sağlık": "Personal Care & Health", "Kadın Giyim & Aksesuar": "Women's Clothing & Accessories",
    "Erkek Giyim & Aksesuar": "Men's Clothing & Accessories", "Çocuk & Bebek": "Kids & Baby",
    "Ev & Yaşam": "Home & Living", "Spor & Outdoor": "Sports & Outdoor",
    "Hobi, Sanat & Koleksiyon": "Hobby, Art & Collectibles", "Kitap, Müzik & Film": "Books, Music & Movies",
    "Kırtasiye & Ofis Malzemeleri": "Stationery & Office Supplies", "Otomotiv Ekipmanları": "Automotive Equipment",
    "Yedek Parça": "Spare Parts", "Jant & Lastik": "Rims & Tires", "Ses & Görüntü Sistemleri": "Audio & Video Systems",
    "Motosiklet Ekipmanları": "Motorcycle Equipment", "Evcil Hayvanlar": "Pets",
    "Evcil Hayvan Ürünleri": "Pet Supplies", "Akvaryum & Balık": "Aquarium & Fish",
    "İş Arayanlar": "Job Seekers", "Eleman Arayanlar": "Employers / Job Openings",
    "Özel Ders Verenler": "Private Tutors", "Nakliye & Lojistik": "Shipping & Logistics",
    "Tadilat & Dekorasyon": "Renovation & Decoration", "Organizasyon & Etkinlik": "Organization & Events",
    "Tamir & Servis": "Repair & Service",
    "Ticari İmarlı": "Commercial Zoned", "Tarımsal": "Agricultural", "Kumaş": "Fabric",
    "Doğal Taş": "Natural Stone", "Kadın": "Women's", "Erkek": "Men's",
    "1–2 Yaş": "1–2 Years", "3–4 Yaş": "3–4 Years", "5–6 Yaş": "5–6 Years",
    "7–8 Yaş": "7–8 Years", "9–10 Yaş": "9–10 Years", "11–12 Yaş": "11–12 Years", "13–14 Yaş": "13–14 Years",
    "Dolap / Gardırop": "Wardrobe / Closet", "Raf / Kitaplık": "Shelf / Bookcase", "Ahşap": "Wood",
    "Nevresim Takımı": "Bedding Set", "Yastık": "Pillow", "Halı / Kilim": "Rug / Carpet",
    "Masa Lambası": "Desk Lamp", "Ayak Lambası": "Floor Lamp", "Dağ Bisikleti": "Mountain Bike",
    "Şehir Bisikleti": "City Bike", "Yol Bisikleti": "Road Bike", "Katlanan Bisiklet": "Folding Bike",
    "Yüzme": "Swimming", "Koşu": "Running", "Köpek": "Dog", "Kuş": "Bird",
    "Balık": "Fish", "Tavşan": "Rabbit", "Davul / Perküsyon": "Drums / Percussion",
    "Saz / Bağlama": "Saz / Baglama", "Flüt": "Flute", "Gitar": "Guitar", "Keman": "Violin",
    "Klima": "Air Conditioner", "Kombi": "Boiler / Combi", "Sanayi": "Industrial",
    "Yerden Isıtma": "Underfloor Heating", "Soba": "Stove", "Plastik": "Plastic",
    "Metal": "Metal", "Platin": "Platinum", "Kanvas": "Canvas", "Suni Deri": "Faux Leather",
    "Terlik": "Slippers", "Sandalet": "Sandals", "Topuklu": "Heels", "Spor / Sneaker": "Sports / Sneakers",
    "Klasik": "Classic", "Minimalist": "Minimalist", "Unisex": "Unisex",
    "Koltuk / Kanepe": "Sofa / Couch", "Yatak": "Bed", "Masa": "Table",
    "Sandalye": "Chair", "Sehpa": "Coffee Table", "Perde": "Curtain / Drapes",
    "Havlu": "Towel", "Yorgan": "Quilt / Blanket", "Hamster": "Hamster",
    "Video Kamera": "Video Camera", "Lens": "Lens", "Tripod": "Tripod",
    "Modem": "Modem", "Tenis": "Tennis", "Voleybol": "Volleyball",
    "Yoga / Pilates": "Yoga / Pilates", "Yarı Eşyalı": "Semi-Furnished",
    "Sıfır (0)": "New (0)", "Sıfır": "New",
    "Action Kamera": "Action Camera", "Flaş / Işık": "Flash / Light",
    "1+0 Stüdyo": "1+0 Studio", "6+1 ve üzeri": "6+1 and above",
    "1–5 yıl": "1–5 years", "6–10 yıl": "6–10 years",
    "11–15 yıl": "11–15 years", "16–20 yıl": "16–20 years",
    "21 yıl ve üzeri": "21 years and above", "Doğalgaz (Merkezi)": "Natural Gas (Central)",
    "Eşyalı": "Furnished", "Konut İmarlı": "Residential Zoned",
    "Doğa Sporları": "Outdoor Sports", "Arsa Tapusu": "Land Title Deed",
    "8 Ayar": "8 Carat", "14 Ayar": "14 Carat", "18 Ayar": "18 Carat",
    "22 Ayar": "22 Carat", "24 Ayar": "24 Carat", "925 Ayar": "925 Purity",
    "950 Ayar": "950 Purity", "999 Ayar": "999 Purity", "1000 Ayar": "1000 Purity",
    "925 Ayar (Sterlin)": "925 Sterling Silver", "800 Ayar": "800 Purity",
    "0–3 Ay": "0–3 Months", "3–6 Ay": "3–6 Months", "6–9 Ay": "6–9 Months",
    "9–12 Ay": "9–12 Months", "12–18 Ay": "12–18 Months", "18–24 Ay": "18–24 Months",
    "24–36 Ay": "24–36 Months", "6–12 Ay": "6–12 Months"
}

known_ar = {
    "1 Serisi": "الفئة 1", "3 Serisi": "الفئة 3", "5 Serisi": "الفئة 5",
    "A Serisi": "الفئة A", "C Serisi": "الفئة C", "E Serisi": "الفئة E",
    "Beyaz": "أبيض", "Gri": "رمادي", "Siyah": "أسود", "Mavi": "أزرق",
    "Kırmızı": "أحمر", "Yeşil": "أخضر", "Sarı": "أصفر", "Turuncu": "برتقالي",
    "Mor": "بنفسجي", "Pembe": "وردي", "Kahverengi": "بني", "Bej": "بيج",
    "Altın": "ذهبي", "Gümüş": "فضي", "Diğer": "أخرى", "Var": "نعم",
    "Yok": "لا", "Benzin": "بنزين", "Dizel": "ديزل", "Hibrit": "هجين",
    "Elektrik": "كهربائي", "Yelken": "شراع", "Manuel": "يدوي",
    "Otomatik": "أوتوماتيك", "Yarı Otomatik": "نصف أوتوماتيك",
    "Minibüs": "ميني باص", "Boyalı": "مطلي", "Kazalı": "حوادث",
    "Hasar Kayıtlı": "سجل الأضرار", "Ağır Hasar Kayıtlı": "سجل أضرار جسيمة",
    "Hatasız": "خالٍ من العيوب", "Hasarsız": "بدون أضرار", "Hasarlı": "متضرر",
    "Değişen / Boyalı": "مستبدل / مطلي", "Değişen": "مستبدل",
    "Motor Tekne": "قارب محرك", "Yelkenli": "قارب شراعي", "Sürat Teknesi": "قارب سريع",
    "Kotra": "قاطع", "Kanotaj / Kayak": "كانو / كايك", "Kompakt": "مدمج",
    "Sıfır": "جديد", "İkinci El": "مستعمل", "Yeni Gibi": "كالجديد",
    "Yenilenmiş": "مجدد", "Az Hasarlı": "أضرار طفيفة",
    "Ağır Hasarlı": "أضرار جسيمة", "Hurda / Parça": "خردة / قطع غيار",
    "Önden Çekiş": "دفع أمامي", "Arkadan İtiş": "دفع خلفي",
    "4 Çekiş (4x4)": "دفع رباعي (4x4)", "AWD (Sürekli 4 Çekiş)": "دفع كلي (AWD)",
    "Stüdyo (1+0)": "ستوديو (1+0)", "Müstakil / Villa": "فيلا / مستقل",
    "Çiftlik Evi": "بيت مزرعة", "Köşk / Konak": "قصر", "Yalı": "منزل شاطئي",
    "İş Hanı": "مبنى مكاتب", "Plaza Katı": "طابق بلازا", "Komple Bina": "مبنى كامل",
    "Depo / Antrepo": "مستودع", "Fabrika": "مصنع", "Atölye": "ورشة",
    "Dükkan / Mağaza": "متجر / محل", "Kafe / Restoran": "مقهى / مطعم",
    "Otel / Butik Otel": "فندق / فندق بوتيك", "Pansiyon": "بنسيون",
    "Tatil Köyü": "قرية عطلات", "Kamp Alanı": "موقع تخييم",
    "Tarla": "حقل", "Arsa (İmarlı)": "أرض للبناء", "Zeytinlik": "بستان زيتون",
    "Bağ / Bahçe": "كرم / حديقة", "Sera": "دفيئة", "Otlak / Mera": "مرعى",
    "Satılık": "للبيع", "Kiralık": "للتأجير", "Günlük Kiralık": "إيجار يومي",
    "Devren Satılık": "للبيع بالتنازل", "Devren Kiralık": "للتأجير بالتنازل",
    "Kat Mülkiyeti": "ملكية طابقية", "Kat İrtifakı": "ارتفاق طابقي",
    "Hisseli Tapu": "سند مشترك", "Arsa Tapulu": "سند أرض",
    "Boş": "شاغر", "Kiracılı": "مؤجر", "Mal Sahibi Oturuyor": "يسكنه المالك",
    "Kuzey": "شمال", "Güney": "جنوب", "Doğu": "شرق", "Batı": "غرب",
    "Kuzeydoğu": "شمال شرق", "Kuzeybatı": "شمال غرب", "Güneydoğu": "جنوب شرق", "Güneybatı": "جنوب غرب",
    "100 Mbps ve altı": "100 ميجابت أو أقل", "101 - 500 Mbps": "101 - 500 ميجابت",
    "501 - 1000 Mbps": "501 - 1000 ميجابت", "1001 Mbps ve üzeri (Wi-Fi 6/6E/7)": "1001 ميجابت فأكثر (Wi-Fi 6/6E/7)",
    "Wi-Fi 5 (802.11ac)": "Wi-Fi 5 (802.11ac)", "Wi-Fi 6 / 6E (802.11ax)": "Wi-Fi 6 / 6E (802.11ax)",
    "Wi-Fi 7 (802.11be)": "Wi-Fi 7 (802.11be)", "Mesh Sistem (Çoklu Nokta)": "نظام Mesh (متعدد النقاط)",
    "Sıfır (Kapalı Kutu)": "جديد (مغلق)", "Yeni Gibi (Kusursuz)": "كالجديد (مثالي)",
    "İyi (Hafif Kullanım İzleri)": "جيد (آثار استخدام طفيفة)", "Kabul Edilebilir (Belirgin Çizik/İz)": "مقبول (آثار واضحة)",
    "Yenilenmiş (Refurbished)": "مجدد", "Arızalı / Parça Niyetine": "معيب / لقطع الغيار",
    "Otomobil": "سيارات", "Motosiklet": "دراجات نارية", "Arazi, SUV & Pickup": "دفع رباعي وبيك أب",
    "Ticari Araçlar": "مركبات تجارية", "Elektrikli Araçlar": "مركبات كهربائية",
    "Deniz Araçları": "مركبات بحرية", "Hasarlı Araçlar": "مركبات متضررة",
    "Daire": "شقة", "Villa / Müstakil": "فيلا / مستقل", "Arsa & Tarla": "أرض وحقل",
    "İş Yeri & Ofis": "مقر عمل ومكتب", "Turistik Tesis": "منشأة سياحية",
    "Cep Telefonu": "هواتف محمولة", "Bilgisayar & Tablet": "كمبيوتر وتابلت",
    "TV, Ses & Görüntü": "تلفزيون وصوت وصورة", "Saat & Giyilebilir Teknoloji": "ساعات وتقنية قابلة للارتداء",
    "Oyun & Konsol": "ألعاب وأجهزة كونسول", "Fotoğraf & Kamera": "تصوير وكاميرات",
    "Ağ & Modem": "شبكات ومودم", "Ev Aletleri": "أجهزة منزلية",
    "Kişisel Bakım & Sağlık": "عناية شخصية وصحة", "Kadın Giyim & Aksesuar": "أزياء وإكسسوارات نسائية",
    "Erkek Giyim & Aksesuar": "أزياء وإكسسوارات رجالية", "Çocuk & Bebek": "أطفال ورضع",
    "Ev & Yaşam": "المنزل والحياة", "Spor & Outdoor": "رياضة وأنشطة خارجية",
    "Hobi, Sanat & Koleksiyon": "هوايات وفنون ومقتنيات", "Kitap, Müzik & Film": "كتب وموسيقى وأفلام",
    "Kırtasiye & Ofis Malzemeleri": "قرطاسية ومستلزمات مكتبية", "Otomotiv Ekipmanları": "معدات سيارات",
    "Yedek Parça": "قطع غيار", "Jant & Lastik": "جنوط وإطارات", "Ses & Görüntü Sistemleri": "أنظمة صوت وصورة",
    "Motosiklet Ekipmanları": "معدات دراجات نارية", "Evcil Hayvanlar": "حيوانات أليفة",
    "Evcil Hayvan Ürünleri": "مستلزمات حيوانات أليفة", "Akvaryum & Balık": "أحواض وأسماك",
    "İş Arayanlar": "باحثون عن عمل", "Eleman Arayanlar": "أصحاب عمل / وظائف",
    "Özel Ders Verenler": "مدرسون خصوصيون", "Nakliye & Lojistik": "شحن ولوجستيات",
    "Tadilat & Dekorasyon": "تجديد وديكور", "Organizasyon & Etkinlik": "تنظيم وفعاليات",
    "Tamir & Servis": "إصلاح وصيانة",
    "Ticari İmarlı": "تجارية معتمدة للبناء", "Tarımsal": "زراعي", "Kumaş": "قماش",
    "Doğal Taş": "حجر طبيعي", "Kadın": "نسائي", "Erkek": "رجالي",
    "1–2 Yaş": "1–2 سنوات", "3–4 Yaş": "3–4 سنوات", "5–6 Yaş": "5–6 سنوات",
    "7–8 Yaş": "7–8 سنوات", "9–10 Yaş": "9–10 سنوات", "11–12 Yaş": "11–12 سنة", "13–14 Yaş": "13–14 سنة",
    "Dolap / Gardırop": "خزانة ملابس", "Raf / Kitaplık": "رف / مكتبة", "Ahşap": "خشب",
    "Nevresim Takımı": "طقم سرير", "Yastık": "وسادة", "Halı / Kilim": "سجاد / كليم",
    "Masa Lambası": "مصباح طاولة", "Ayak Lambası": "مصباح أرضي", "Dağ Bisikleti": "دراجة جبلية",
    "Şehir Bisikleti": "دراجة مدينة", "Yol Bisikleti": "دراجة طريق", "Katlanan Bisiklet": "دراجة قابلة للطي",
    "Yüzme": "سباحة", "Koşu": "جري", "Köpek": "كلب", "Kuş": "طائر",
    "Balık": "سمك", "Tavşan": "أرنب", "Davul / Perküsyon": "طبول / إيقاع",
    "Saz / Bağlama": "ساز / باقلاما", "Flüt": "ناي", "Gitar": "جيتار", "Keman": "كمان",
    "Klima": "مكيف هواء", "Kombi": "غلاية / كومبي", "Sanayi": "صناعي",
    "Yerden Isıtma": "تدفئة أرضية", "Soba": "مدفأة", "Plastik": "بلاستيك",
    "Metal": "معدن", "Platin": "بلاتين", "Kanvas": "قماش كانفاس", "Suni Deri": "جلد صناعي",
    "Terlik": "نعال / شبشب", "Sandalet": "صندل", "Topuklu": "كعب عالي", "Spor / Sneaker": "رياضي / سنيكرز",
    "Klasik": "كلاسيكي", "Minimalist": "أقلية / تبسيط", "Unisex": "للجنسين",
    "Koltuk / Kanepe": "أريكة / كنبة", "Yatak": "سرير", "Masa": "طاولة",
    "Sandalye": "كرسي", "Sehpa": "طاولة قهوة", "Perde": "ستائر",
    "Havlu": "منشفة", "Yorgan": "لحاف / بطانية", "Hamster": "هامستر",
    "Video Kamera": "كاميرا فيديو", "Lens": "عدسة", "Tripod": "حامل ثلاثي",
    "Modem": "مودم", "Tenis": "تنس", "Voleybol": "كرة طائرة",
    "Yoga / Pilates": "يوجا / بيلاتس", "Yarı Eşyalı": "مؤثث جزئياً",
    "Sıfır (0)": "جديد (0)", "Sıfır": "جديد",
    "Action Kamera": "كاميرا أكشن", "Flaş / Işık": "فلاش / إضاءة",
    "1+0 Stüdyo": "ستوديو 1+0", "6+1 ve üzeri": "6+1 فأكثر",
    "1–5 yıl": "1–5 سنوات", "6–10 yıl": "6–10 سنوات",
    "11–15 yıl": "11–15 سنة", "16–20 yıl": "16–20 سنة",
    "21 yıl ve üzeri": "21 سنة فأكثر", "Doğalgaz (Merkezi)": "غاز طبيعي (مركزي)",
    "Eşyalı": "مؤثث", "Konut İmarlı": "سكني معتمد للبناء",
    "Doğa Sporları": "رياضات خارجية", "Arsa Tapusu": "سند ملكية أرض",
    "8 Ayar": "عيار 8", "14 Ayar": "عيار 14", "18 Ayar": "عيار 18",
    "22 Ayar": "عيار 22", "24 Ayar": "عيار 24", "925 Ayar": "عيار 925",
    "950 Ayar": "عيار 950", "999 Ayar": "عيار 999", "1000 Ayar": "عيار 1000",
    "925 Ayar (Sterlin)": "فضة استرليني عيار 925", "800 Ayar": "عيار 800",
    "0–3 Ay": "0–3 أشهر", "3–6 Ay": "3–6 أشهر", "6–9 Ay": "6–9 أشهر",
    "9–12 Ay": "9–12 أشهر", "12–18 Ay": "12–18 شهراً", "18–24 Ay": "18–24 شهراً",
    "24–36 Ay": "24–36 شهراً", "6–12 Ay": "6–12 أشهر"
}

known_ru = {
    "1 Serisi": "1 Серия", "3 Serisi": "3 Серия", "5 Serisi": "5 Серия",
    "A Serisi": "A-Класс", "C Serisi": "C-Класс", "E Serisi": "E-Класс",
    "Beyaz": "Белый", "Gri": "Серый", "Siyah": "Чёрный", "Mavi": "Синий",
    "Kırmızı": "Красный", "Yeşil": "Зелёный", "Sarı": "Жёлтый", "Turuncu": "Оранжевый",
    "Mor": "Фиолетовый", "Pembe": "Розовый", "Kahverengi": "Коричневый", "Bej": "Бежевый",
    "Altın": "Золотой", "Gümüş": "Серебристый", "Diğer": "Другое", "Var": "Есть",
    "Yok": "Нет", "Benzin": "Бензин", "Dizel": "Дизель", "Hibrit": "Гибрид",
    "Elektrik": "Электричество", "Yelken": "Парус", "Manuel": "Ручная",
    "Otomatik": "Автомат", "Yarı Otomatik": "Полуавтомат",
    "Minibüs": "Микроавтобус", "Boyalı": "Крашеный", "Kazalı": "После ДТП",
    "Hasar Kayıtlı": "С записью о ДТП", "Ağır Hasar Kayıtlı": "Серьёзные повреждения",
    "Hatasız": "Без дефектов", "Hasarsız": "Без повреждений", "Hasarlı": "Повреждённый",
    "Değişen / Boyalı": "Заменено / Покрашено", "Değişen": "Заменено",
    "Motor Tekne": "Моторная лодка", "Yelkenli": "Парусник", "Sürat Teknesi": "Катер",
    "Kotra": "Катер", "Kanotaj / Kayak": "Каное / Каяк", "Kompakt": "Компактный",
    "Sıfır": "Новый", "İkinci El": "Б/у", "Yeni Gibi": "Как новый",
    "Yenilenmiş": "Восстановленный", "Az Hasarlı": "Незначительные повреждения",
    "Ağır Hasarlı": "Сильные повреждения", "Hurda / Parça": "На запчасти",
    "Önden Çekiş": "Передний привод", "Arkadan İtiş": "Задний привод",
    "4 Çekiş (4x4)": "Полный привод (4x4)", "AWD (Sürekli 4 Çekiş)": "Постоянный полный привод (AWD)",
    "Stüdyo (1+0)": "Студия (1+0)", "Müstakil / Villa": "Особняк / Вилла",
    "Çiftlik Evi": "Фермерский дом", "Köşk / Konak": "Особняк", "Yalı": "Дом у воды",
    "İş Hanı": "Офисное здание", "Plaza Katı": "Этаж бизнес-центра", "Komple Bina": "Зданиe целиком",
    "Depo / Antrepo": "Склад", "Fabrika": "Фабрика", "Atölye": "Мастерская",
    "Dükkan / Mağaza": "Магазин", "Kafe / Restoran": "Кафе / Ресторан",
    "Otel / Бутик Otel": "Отель / Бутик-отель", "Pansiyon": "Пансионат",
    "Tatil Köyü": "Курортный поселок", "Kamp Alanı": "Кемпинг",
    "Tarla": "Поле", "Arsa (İmarlı)": "Участок под застройку", "Zeytinlik": "Оливковая роща",
    "Bağ / Bahçe": "Виноградник / Сад", "Sera": "Теплица", "Otlak / Mera": "Пастбище",
    "Satılık": "Продажа", "Kiralık": "Аренда", "Günlük Kiralık": "Посуточная аренда",
    "Devren Satılık": "Продажа бизнеса", "Devren Kiralık": "Переуступка аренды",
    "Kat Mülkiyeti": "Частная собственность на этаж", "Kat İrtifakı": "Право застройки этажа",
    "Hisseli Tapu": "Долевая собственность", "Arsa Tapulu": "Земельный акт",
    "Boş": "Свободно", "Kiracılı": "С арендатором", "Mal Sahibi Oturuyor": "Проживает собственник",
    "Kuzey": "Север", "Güney": "Юг", "Doğu": "Восток", "Batı": "Запад",
    "Kuzeydoğu": "Северо-восток", "Kuzeybatı": "Северо-запад", "Güneydoğu": "Юго-восток", "Güneybatı": "Юго-запад",
    "100 Mbps ve altı": "100 Мбит/с и ниже", "101 - 500 Mbps": "101 - 500 Мбит/с",
    "501 - 1000 Mbps": "501 - 1000 Мбит/с", "1001 Mbps ve üzeri (Wi-Fi 6/6E/7)": "1001 Мбит/с и выше (Wi-Fi 6/6E/7)",
    "Wi-Fi 5 (802.11ac)": "Wi-Fi 5 (802.11ac)", "Wi-Fi 6 / 6E (802.11ax)": "Wi-Fi 6 / 6E (802.11ax)",
    "Wi-Fi 7 (802.11be)": "Wi-Fi 7 (802.11be)", "Mesh Sistem (Çoklu Nokta)": "Mesh система (многоточечная)",
    "Sıfır (Kapalı Kutu)": "Новое (в запечатанной коробке)", "Yeni Gibi (Kusursuz)": "Как новое (идеальное)",
    "İyi (Hafif Kullanım İzleri)": "Хорошее (небольшие следы)", "Kabul Edilebilir (Belirgin Çizik/İz)": "Приемлемое (заметные следы)",
    "Yenilenmiş (Refurbished)": "Восстановленное", "Arızalı / Parça Niyetine": "Неисправное / На запчасти",
    "Otomobil": "Легковые автомобили", "Motosiklet": "Мотоциклы", "Arazi, SUV & Pickup": "Внедорожники и пикапы",
    "Ticari Araçlar": "Коммерческий транспорт", "Elektrikli Araçlar": "Электромобили",
    "Deniz Araçları": "Водный транспорт", "Hasarlı Araçlar": "Повреждённые автомобили",
    "Daire": "Квартиры", "Villa / Müstakil": "Виллы и дома", "Arsa & Tarla": "Земля и участки",
    "İş Yeri & Ofis": "Коммерческая недвижимость", "Turistik Tesis": "Туристические объекты",
    "Cep Telefonu": "Мобильные телефоны", "Bilgisayar & Tablet": "Компьютеры и планшеты",
    "TV, Ses & Görüntü": "ТВ, аудио и видео", "Saat & Giyilebilir Teknoloji": "Часы и гаджеты",
    "Oyun & Konsol": "Игры и приставки", "Fotoğraf & Kamera": "Фото и видеокамеры",
    "Ağ & Modem": "Сетевое оборудование", "Ev Aletleri": "Бытовая техника",
    "Kişisel Bakım & Sağlık": "Красота и здоровье", "Kadın Giyim & Aksesuar": "Женская одежда и обувь",
    "Erkek Giyim & Aksesuar": "Мужская одежда и обувь", "Çocuk & Bebek": "Детские товары",
    "Ev & Yaşam": "Дом и интерьер", "Spor & Outdoor": "Спорт и отдых",
    "Hobi, Sanat & Koleksiyon": "Хобби и коллекционирование", "Kitap, Müzik & Film": "Книги, музыка и фильмы",
    "Kırtasiye & Ofis Malzemeleri": "Канцелярия и офис", "Otomotiv Ekipmanları": "Автотовары",
    "Yedek Parça": "Запчасти", "Jant & Lastik": "Диски и шины", "Ses & Görüntü Sistemleri": "Аудио и видео системы",
    "Motosiklet Ekipmanları": "Мотоэкипировка", "Evcil Hayvanlar": "Домашние животные",
    "Evcil Hayvan Ürünleri": "Зоотовары", "Akvaryum & Balık": "Аквариумистика",
    "İş Arayanlar": "Ищут работу", "Eleman Arayanlar": "Вакансии",
    "Özel Ders Verenler": "Репетиторы", "Nakliye & Lojistik": "Грузоперевозки",
    "Tadilat & Dekorasyon": "Ремонт и декор", "Organizasyon & Etkinlik": "Организация мероприятий",
    "Tamir & Servis": "Ремонт и сервис",
    "Ticari İmarlı": "Коммерческая застройка", "Tarımsal": "Сельскохозяйственный", "Kumaş": "Ткань",
    "Doğal Taş": "Натуральный камень", "Kadın": "Женская", "Erkek": "Мужская",
    "1–2 Yaş": "1–2 года", "3–4 Yaş": "3–4 года", "5–6 Yaş": "5–6 лет",
    "7–8 Yaş": "7–8 лет", "9–10 Yaş": "9–10 лет", "11–12 Yaş": "11–12 лет", "13–14 Yaş": "13–14 лет",
    "Dolap / Gardırop": "Шкаф / Гардероб", "Raf / Kitaplık": "Полка / Книжный шкаф", "Ahşap": "Дерево",
    "Nevresim Takımı": "Постельное белье", "Yastık": "Подушка", "Halı / Kilim": "Ковер / Коврик",
    "Masa Lambası": "Настольная лампа", "Ayak Lambası": "Торшер", "Dağ Bisikleti": "Горный велосипед",
    "Şehir Bisikleti": "Городской велосипед", "Yol Bisikleti": "Шоссейный велосипед", "Katlanan Bisiklet": "Складной велосипед",
    "Yüzme": "Плавание", "Koşu": "Бег", "Köpek": "Собака", "Kuş": "Птица",
    "Balık": "Рыба", "Tavşan": "Кролик", "Davul / Perküsyon": "Барабаны / Перкуссия",
    "Saz / Bağlama": "Саз / Баглама", "Flüt": "Флейта", "Gitar": "Гитара", "Keman": "Скрипка",
    "Klima": "Кондиционер", "Kombi": "Котел / Комби", "Sanayi": "Промышленный",
    "Yerden Isıtma": "Теплый пол", "Soba": "Печь", "Plastik": "Пластик",
    "Metal": "Металл", "Platin": "Платина", "Kanvas": "Холст", "Suni Deri": "Искусственная кожа",
    "Terlik": "Тапочки", "Sandalet": "Сандалии", "Topuklu": "Туфли на каблуке", "Spor / Sneaker": "Спортивные / Кроссовки",
    "Klasik": "Классический", "Minimalist": "Минималистский", "Unisex": "Унисекс",
    "Koltuk / Kanepe": "Диван / Кушетка", "Yatak": "Кровать", "Masa": "Стол",
    "Sandalye": "Стул", "Sehpa": "Журнальный столик", "Perde": "Шторы / Портьеры",
    "Havlu": "Полотенце", "Yorgan": "Одеяло / Плед", "Hamster": "Хомяк",
    "Video Kamera": "Видеокамера", "Lens": "Объектив", "Tripod": "Штатив",
    "Modem": "Модем", "Tenis": "Теннис", "Voleybol": "Волейбол",
    "Yoga / Pilates": "Йога / Пилатес", "Yarı Eşyalı": "Частично меблирована",
    "Sıfır (0)": "Новый (0)", "Sıfır": "Новый",
    "Action Kamera": "Экшн-камера", "Flaş / Işık": "Вспышка / Свет",
    "1+0 Stüdyo": "Студия 1+0", "6+1 ve üzeri": "6+1 и более",
    "1–5 yıl": "1–5 лет", "6–10 yıl": "6–10 лет",
    "11–15 yıl": "11–15 лет", "16–20 yıl": "16–20 лет",
    "21 yıl ve üzeri": "21 год и более", "Doğalgaz (Merkezi)": "Газ (Центральный)",
    "Eşyalı": "С мебелью", "Konut İmarlı": "Жилая застройка",
    "Doğa Sporları": "Спорт на открытом воздухе", "Arsa Tapusu": "Земельный акт",
    "8 Ayar": "8 карат", "14 Ayar": "14 карат", "18 Ayar": "18 карат",
    "22 Ayar": "22 карат", "24 Ayar": "24 карат", "925 Ayar": "Проба 925",
    "950 Ayar": "Проба 950", "999 Ayar": "Проба 999", "1000 Ayar": "Проба 1000",
    "925 Ayar (Sterlin)": "Стерлинговое серебро (925)", "800 Ayar": "Проба 800",
    "0–3 Ay": "0–3 месяца", "3–6 Ay": "3–6 месяцев", "6–9 Ay": "6–9 месяцев",
    "9–12 Ay": "9–12 месяцев", "12–18 Ay": "12–18 месяцев", "18–24 Ay": "18–24 месяца",
    "24–36 Ay": "24–36 месяцев", "6–12 Ay": "6–12 месяцев"
}

def translate_label(val, tr_label, lang):
    if lang == "tr": return tr_label
    if lang == "en":
        if tr_label in known_en: return known_en[tr_label]
        res = tr_label.replace(" Serisi", " Series").replace(" serisi", " series")
        return res
    if lang == "ar":
        if tr_label in known_ar: return known_ar[tr_label]
        res = tr_label.replace(" Serisi", " - الفئة").replace(" serisi", " - الفئة")
        return res
    if lang == "ru":
        if tr_label in known_ru: return known_ru[tr_label]
        res = tr_label.replace(" Serisi", " Серия").replace(" serisi", " Серия")
        return res
    return tr_label

added_count = 0
for val, tr_label in sorted(all_options.items()):
    keys_to_set = [f"opt_{val}"]
    if val in option_value_map:
        keys_to_set.append(f"opt_{option_value_map[val]}")
    if val in ENGLISH_KEY_ALIASES:
        for alias in ENGLISH_KEY_ALIASES[val]:
            keys_to_set.append(f"opt_{alias}")
    
    # Deduplicate while preserving order
    unique_keys = []
    for k in keys_to_set:
        if k not in unique_keys:
            unique_keys.append(k)
            
    for key in unique_keys:
        if key not in tr_arb:
            added_count += 1
        tr_arb[key] = tr_label
        en_arb[key] = translate_label(val, tr_label, "en")
        ar_arb[key] = translate_label(val, tr_label, "ar")
        ru_arb[key] = translate_label(val, tr_label, "ru")

print(f"Added/Updated {added_count} option keys cleanly without false positives.")
print(f"Final key counts -> TR: {len(tr_arb)}, EN: {len(en_arb)}, AR: {len(ar_arb)}, RU: {len(ru_arb)}")

write_arb(tr_path, tr_arb)
write_arb(en_path, en_arb)
write_arb(ar_path, ar_arb)
write_arb(ru_path, ru_arb)
print("Successfully updated all 4 ARB files cleanly and exhaustively!")
