#!/usr/bin/env python3
"""
generate_mock_data.py — Teqlif ML Pipeline Mock Data Generator

6 JSON dosyası üretir:
  mock_01_listings.json          — 600 ilan (PostgreSQL: listings)
  mock_02_user_interactions.json — ~5000 etkileşim (PostgreSQL: user_interactions)
  mock_03_user_interests.json    — ~230 kategori ilgi skoru (PostgreSQL: user_interests)
  mock_04_feed_analytics.json    — ~3000 feed eventi (ClickHouse: feed_analytics)
  mock_05_search_events.json     — ~600 arama eventi (ClickHouse: search_events)
  mock_06_swipe_live.json        — ~300 swipe live eventi (ClickHouse: swipe_live_events)

Insert scriptleri listing_idx alanını kullanarak gerçek DB ID'leriyle eşleştirir.

Çalıştırma: python documents/mock_data/generate_mock_data.py
Bağımlılık: yok (stdlib only)
"""

import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

RNG = random.Random(42)
OUT_DIR = Path(__file__).parent
NOW = datetime.now(tz=timezone.utc)


# ── Kullanıcı Grupları ────────────────────────────────────────────────────────

GROUPS: dict[str, dict] = {
    "A": {
        "user_ids": [1, 2, 3, 4, 5, 6, 10, 11, 12, 13],
        "primary_cat": "vasita",
        "secondary_cat": "elektronik",
    },
    "B": {
        "user_ids": [16, 17, 19, 20, 21, 22, 23, 24, 25, 26],
        "primary_cat": "emlak",
        "secondary_cat": "ev-yasam",
    },
    "C": {
        "user_ids": [27, 28, 29, 30, 31, 32, 386, 387, 388, 389],
        "primary_cat": "elektronik",
        "secondary_cat": "kitap-hobi",
    },
    "D": {
        "user_ids": [390, 391, 392, 393, 394, 395, 396, 397, 398, 399],
        "primary_cat": "giyim-aksesuar",
        "secondary_cat": "spor-outdoor",
    },
    "E": {
        "user_ids": [400, 401, 402, 403, 404, 405, 406, 407, 408, 409],
        "primary_cat": None,
        "secondary_cat": None,
    },
}

ALL_USER_IDS = [uid for g in GROUPS.values() for uid in g["user_ids"]]
USER_GROUP: dict[int, str] = {uid: gk for gk, gv in GROUPS.items() for uid in gv["user_ids"]}

CATEGORIES = {
    "vasita":         ["otomobil", "motosiklet", "elektrikli-arac", "kamyonet-minibus", "vasita-yedek-parca"],
    "emlak":          ["daire", "mustakil-ev-villa", "arsa", "is-yeri-ofis"],
    "elektronik":     ["cep-telefonu", "bilgisayar-laptop", "tablet", "tv-monitor", "oyun-konsolu"],
    "giyim-aksesuar": ["kadin-giyim", "erkek-giyim", "ayakkabi", "canta-cuzdan", "saat"],
    "ev-yasam":       ["mobilya", "mutfak-pisirme", "ev-tekstili", "dekorasyon-aydinlatma"],
    "spor-outdoor":   ["bisiklet", "fitness-spor-salonu", "outdoor-kamp", "takim-sporlari"],
    "kitap-hobi":     ["roman-hikaye", "muzik-aleti", "koleksiyon", "ders-kitabi-akademik"],
    "diger":          ["evcil-hayvan", "oyuncak-cocuk-oyun", "saglik-guzellik"],
}

# Stream ID → (category, subcategory)  — T01'den gelen güncel veri
STREAM_CATS: dict[int, tuple] = {
    **{i: ("vasita", None)         for i in range(4, 9)},
    **{i: ("elektronik", None)     for i in range(9, 14)},
    **{i: ("emlak", None)          for i in range(14, 19)},
    **{i: ("giyim-aksesuar", None) for i in range(19, 24)},
    **{i: ("spor-outdoor", None)   for i in range(24, 29)},
    **{i: ("diger", None)          for i in range(29, 34)},
}

LOCATIONS = [
    ("İstanbul", "Kadıköy"),
    ("İstanbul", "Beşiktaş"),
    ("İstanbul", "Ümraniye"),
    ("Ankara", "Çankaya"),
    ("Ankara", "Keçiören"),
    ("İzmir", "Bornova"),
    ("İzmir", "Karşıyaka"),
    ("Bursa", "Osmangazi"),
    ("Antalya", "Muratpaşa"),
    ("Antalya", "Konyaaltı"),
    ("Adana", "Seyhan"),
    ("Konya", "Selçuklu"),
]


# ── Araç İçerikleri ──────────────────────────────────────────────────────────

_OTOMOBIL = {
    "brands": ["Volkswagen", "BMW", "Mercedes", "Ford", "Toyota", "Renault", "Fiat", "Honda", "Hyundai", "Kia"],
    "models": {
        "Volkswagen": ["Passat", "Golf", "Polo", "Tiguan"],
        "BMW":        ["3 Serisi", "5 Serisi", "X3", "X5"],
        "Mercedes":   ["C Serisi", "E Serisi", "GLC", "A Serisi"],
        "Ford":       ["Focus", "Fiesta", "Mondeo", "Kuga"],
        "Toyota":     ["Corolla", "Yaris", "RAV4", "Camry"],
        "Renault":    ["Clio", "Megane", "Symbol", "Duster"],
        "Fiat":       ["Egea", "Linea", "500", "Tipo"],
        "Honda":      ["Civic", "CR-V", "Jazz", "HR-V"],
        "Hyundai":    ["i20", "i30", "Tucson", "Elantra"],
        "Kia":        ["Picanto", "Sportage", "Ceed", "Sorento"],
    },
    "fuels": ["Benzin", "Dizel", "LPG", "Hibrit"],
    "transmissions": ["Manuel", "Otomatik"],
    "price_range": (120_000, 2_500_000),
    "km_range": (5_000, 250_000),
    "year_range": (2010, 2024),
}

_MOTOSIKLET = {
    "brands": ["Honda", "Yamaha", "Kawasaki", "Suzuki", "BMW", "KTM"],
    "models": {
        "Honda":    ["CB500F", "CB650R", "PCX 125", "Forza 350"],
        "Yamaha":   ["MT-07", "MT-09", "XMAX 300", "Nmax 125"],
        "Kawasaki": ["Z650", "Ninja 400", "Versys 650", "Z900"],
        "Suzuki":   ["SV650", "GSX-S750", "Burgman 400"],
        "BMW":      ["R1250GS", "F850GS", "G310R"],
        "KTM":      ["Duke 390", "Duke 790", "Adventure 890"],
    },
    "price_range": (50_000, 400_000),
    "km_range": (1_000, 60_000),
    "year_range": (2015, 2024),
}

_ELEKTRONIK_CEP = {
    "brands": ["Apple", "Samsung", "Xiaomi", "Huawei", "OnePlus"],
    "models": {
        "Apple":   ["iPhone 14", "iPhone 14 Pro", "iPhone 15", "iPhone 15 Pro", "iPhone 13"],
        "Samsung": ["Galaxy S23", "Galaxy A54", "Galaxy S22", "Galaxy A34"],
        "Xiaomi":  ["Redmi Note 12", "POCO X5 Pro", "Redmi 12C"],
        "Huawei":  ["P50 Pro", "Nova 11"],
        "OnePlus": ["11", "Nord 2T", "10 Pro"],
    },
    "storage": ["128GB", "256GB", "512GB"],
    "price_range": (8_000, 70_000),
}

_LAPTOP = {
    "brands": ["Apple", "Dell", "HP", "Lenovo", "ASUS", "MSI"],
    "models": {
        "Apple":  ["MacBook Air M1", "MacBook Air M2", "MacBook Pro 14", "MacBook Pro 16"],
        "Dell":   ["XPS 13", "XPS 15", "Inspiron 15", "Latitude 5430"],
        "HP":     ["Spectre x360", "EliteBook 840", "Pavilion 15", "Omen 15"],
        "Lenovo": ["ThinkPad T14", "IdeaPad 5", "Legion 5", "Yoga 9"],
        "ASUS":   ["ZenBook 14", "VivoBook 15", "ROG Strix G15"],
        "MSI":    ["Raider GE76", "Katana GF76", "Modern 15"],
    },
    "ram": ["8GB", "16GB", "32GB"],
    "storage": ["256GB SSD", "512GB SSD", "1TB SSD"],
    "price_range": (15_000, 100_000),
}

_KADIN_GIYIM_BRANDS = ["Zara", "H&M", "Mango", "Koton", "LC Waikiki", "Bershka"]
_ERKEK_GIYIM_BRANDS = ["Zara", "H&M", "Koton", "LC Waikiki", "Mavi", "Pull&Bear"]
_AYAKKABI_BRANDS    = ["Nike", "Adidas", "Puma", "New Balance", "Converse", "Skechers"]
_AYAKKABI_MODELS    = {
    "Nike":        ["Air Max 90", "Air Force 1", "Pegasus 40", "React"],
    "Adidas":      ["Ultraboost 22", "Superstar", "Stan Smith", "NMD R1"],
    "Puma":        ["RS-X", "Future Rider", "Suede Classic"],
    "New Balance": ["574", "990v5", "Fresh Foam 1080"],
    "Converse":    ["Chuck Taylor All Star", "Run Star Hike"],
    "Skechers":    ["Go Walk", "Arch Fit"],
}
_SAAT_BRANDS = ["Casio", "Tissot", "Fossil", "Seiko", "Omega"]
_SAAT_MODELS = {
    "Casio":  ["G-Shock GA-100", "Edifice EFV-530", "Pro Trek PRW-6000"],
    "Tissot": ["T-Classic", "PRX", "Le Locle"],
    "Fossil": ["Neutra Chronograph", "Grant"],
    "Seiko":  ["Presage", "5 Sports", "Prospex"],
    "Omega":  ["Speedmaster", "Seamaster"],
}
_BISIKLET_BRANDS  = ["Trek", "Giant", "Specialized", "Decathlon"]
_BISIKLET_MODELS  = {
    "Trek":       ["Marlin 5", "FX 3", "Precaliber"],
    "Giant":      ["Talon 3", "Contend 3", "ATX 830"],
    "Specialized":["Rockhopper", "Sirrus", "Crosstrail"],
    "Decathlon":  ["Riverside 500", "Rockrider ST 100", "Elops 520"],
}


# ── Yardımcılar ───────────────────────────────────────────────────────────────

def pick(lst: list):
    return RNG.choice(lst)

def wpick(items: list, weights: list):
    return RNG.choices(items, weights=weights, k=1)[0]

def rand_dt(min_days: int, max_days: int) -> datetime:
    days  = RNG.randint(min_days, max_days)
    hours = RNG.randint(0, 23)
    mins  = RNG.randint(0, 59)
    return NOW - timedelta(days=days, hours=hours, minutes=mins)

def recent_ts(max_days: int = 120) -> datetime:
    """Son max_days günde, son 30 güne yoğunlaşan dağılım."""
    r    = RNG.random() ** 1.6
    days = int(r * max_days)
    return NOW - timedelta(days=days, hours=RNG.randint(0, 23))

def fmt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def img(category: str, idx: int, suffix: str = "") -> str:
    slug = category.replace("-", "")[:6]
    return f"https://picsum.photos/seed/{slug}{idx}{suffix}/800/600"


# ── İlan İçerik Üreticiler ────────────────────────────────────────────────────

def _vasita_otomobil(idx: int) -> dict:
    brand = pick(_OTOMOBIL["brands"])
    model = pick(_OTOMOBIL["models"].get(brand, ["Sedan"]))
    fuel  = pick(_OTOMOBIL["fuels"])
    trans = pick(_OTOMOBIL["transmissions"])
    year  = RNG.randint(*_OTOMOBIL["year_range"])
    km    = RNG.randint(*_OTOMOBIL["km_range"])
    price = float(RNG.randint(*_OTOMOBIL["price_range"]))
    km_s  = f"{km:,}".replace(",", ".")
    title = f"{year} {brand} {model} — {fuel}, {km_s}km"[:95]
    desc  = (
        f"{year} model {brand} {model} satılıyorum. {km_s} km'de, {fuel} yakıt, "
        f"{trans} vites. Bakımları zamanında yapıldı, herhangi bir hasar yok. "
        f"Kaskosu ve muayenesi geçerli. Değişensiz, boyasız. Test sürüşü yapılabilir."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["used", "like_new"]),
        "extra_fields": {"year": year, "mileage": km, "fuel_type": fuel, "transmission": trans},
    }

def _vasita_motosiklet(idx: int) -> dict:
    brand = pick(_MOTOSIKLET["brands"])
    model = pick(_MOTOSIKLET["models"].get(brand, ["Sport"]))
    year  = RNG.randint(*_MOTOSIKLET["year_range"])
    km    = RNG.randint(*_MOTOSIKLET["km_range"])
    price = float(RNG.randint(*_MOTOSIKLET["price_range"]))
    km_s  = f"{km:,}".replace(",", ".")
    title = f"{year} {brand} {model}, {km_s}km"[:95]
    desc  = (
        f"{year} {brand} {model} satılıyorum. {km_s} km'de, bakımlı ve kaskolu. "
        f"Takas yapılır, fiyat görüşülür. Mükemmel sürüş performansı, yol tutuşu üst düzey."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["used", "like_new"]),
        "extra_fields": {"year": year, "mileage": km},
    }

def _vasita_elektrikli(idx: int) -> dict:
    brands = ["Xiaomi", "Segway", "Vestel", "Ninebot"]
    brand  = pick(brands)
    models_map = {
        "Xiaomi":   ["Mi Scooter Pro 2", "Mi Scooter 4"],
        "Segway":   ["Ninebot E22", "Ninebot MAX G30"],
        "Vestel":   ["e-Scooter S1"],
        "Ninebot":  ["KickScooter F40", "KickScooter E25"],
    }
    model  = pick(models_map.get(brand, [brand + " Scooter"]))
    km     = RNG.randint(100, 4000)
    price  = float(RNG.randint(8_000, 80_000))
    title  = f"Elektrikli scooter — {brand} {model}"[:95]
    desc   = (
        f"{brand} {model} elektrikli scooter satılıyorum. {km} km kullanılmış, "
        f"şarj cihazı dahil. Şehir içi ulaşım için ideal, pil kapasitesi iyi durumda."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": {"mileage": km},
    }

def _vasita_kamyonet(idx: int) -> dict:
    brands = ["Ford", "Fiat", "Mercedes", "Volkswagen", "Renault"]
    mmap   = {
        "Ford":       ["Transit", "Transit Custom", "Connect"],
        "Fiat":       ["Doblo Cargo", "Ducato"],
        "Mercedes":   ["Sprinter", "Vito"],
        "Volkswagen": ["Crafter", "Transporter"],
        "Renault":    ["Master", "Trafic"],
    }
    brand = pick(brands)
    model = pick(mmap.get(brand, [brand + " Cargo"]))
    year  = RNG.randint(2012, 2024)
    km    = RNG.randint(50_000, 350_000)
    price = float(RNG.randint(200_000, 1_800_000))
    km_s  = f"{km:,}".replace(",", ".")
    title = f"{year} {brand} {model} kamyonet/ticari araç"[:95]
    desc  = (
        f"Satılık ticari araç. {brand} {model}, {year} model, {km_s} km'de. "
        f"Dizel motor, bakımları düzenli yapılmış. Taşıma kapasitesi yüksek."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["used", "like_new"]),
        "extra_fields": {"year": year, "mileage": km, "fuel_type": "Dizel", "transmission": "Manuel"},
    }

def _vasita_parca(idx: int) -> dict:
    items = [
        ("Bosch", "Akü 60Ah", 1_500, 4_000),
        ("NGK", "Ateşleme Buji Seti", 200, 800),
        ("Mann Filter", "Yağ Filtresi", 150, 500),
        ("Gates", "Triger Kayışı Seti", 800, 2_500),
        ("Bosch", "Silecek Takımı", 300, 800),
        ("Valeo", "Debriyaj Seti", 2_000, 6_000),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} — orijinal yedek parça"[:95]
    desc  = (
        f"Araç yedek parçası satılıyorum. {brand} {model}, kutusunda açılmamış orijinal ürün. "
        f"Araç değişikliği nedeniyle kullanılmadı."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": "new",
        "extra_fields": None,
    }

def _emlak_daire(idx: int, province: str, district: str) -> dict:
    rooms   = pick(["1+1", "2+1", "3+1", "4+1"])
    sqm     = RNG.randint(50, 200)
    floor   = RNG.randint(1, 12)
    price   = float(RNG.randint(800_000, 8_000_000))
    listing_type = pick(["Satılık", "Kiralık"])
    title   = f"{listing_type} {rooms} daire — {district}"[:95]
    desc    = (
        f"{listing_type} {rooms} daire, brüt {sqm}m², {floor}. kat. "
        f"Merkezi ısıtma, asansörlü bina. {district} merkezde, toplu taşımaya yakın. "
        f"Güneş gören cephe, ferah oda düzeni."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": pick(["new", "used"]),
        "extra_fields": {"room_count": rooms, "gross_sqm": sqm, "floor": floor},
    }

def _emlak_villa(idx: int, province: str, district: str) -> dict:
    rooms = pick(["3+1", "4+1", "5+1"])
    sqm   = RNG.randint(120, 450)
    price = float(RNG.randint(2_000_000, 20_000_000))
    title = f"Satılık {rooms} müstakil ev / villa — {district}"[:95]
    desc  = (
        f"Müstakil ev satılıyor. {rooms}, {sqm}m² kullanım alanı. "
        f"Bahçeli, 2 katlı yapı. {district} mevkii, sakin ve güvenli semt. "
        f"Kapalı otopark, özel bahçe."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": pick(["new", "used"]),
        "extra_fields": {"room_count": rooms, "gross_sqm": sqm},
    }

def _emlak_arsa(idx: int, province: str, district: str) -> dict:
    sqm   = RNG.randint(300, 5_000)
    price = float(RNG.randint(500_000, 15_000_000))
    title = f"Satılık arsa — {province}, {district}"[:95]
    desc  = (
        f"Satılık {sqm}m² imarlı arsa. Köşe parsel, yola cepheli. "
        f"{district} gelişim bölgesinde yatırımlık. Tapu temiz, müstakil."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": None,
        "extra_fields": {"gross_sqm": sqm},
    }

def _emlak_isyeri(idx: int, province: str, district: str) -> dict:
    sqm   = RNG.randint(40, 300)
    price = float(RNG.randint(400_000, 6_000_000))
    listing_type = pick(["Satılık", "Kiralık"])
    title = f"{listing_type} iş yeri / ofis — {district}, {sqm}m²"[:95]
    desc  = (
        f"{listing_type} {sqm}m² ofis alanı. {district} ana cadde üzeri, zemin kat. "
        f"Otopark mevcut, klimalı, hazır ofis kurulumu yapılabilir."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": pick(["new", "used"]),
        "extra_fields": {"gross_sqm": sqm},
    }

def _elektronik_cep(idx: int) -> dict:
    brand   = pick(_ELEKTRONIK_CEP["brands"])
    model   = pick(_ELEKTRONIK_CEP["models"].get(brand, [brand + " Pro"]))
    storage = pick(_ELEKTRONIK_CEP["storage"])
    price   = float(RNG.randint(*_ELEKTRONIK_CEP["price_range"]))
    battery = RNG.randint(82, 99)
    title   = f"{brand} {model} {storage} — az kullanılmış"[:95]
    desc    = (
        f"{brand} {model} satılıyorum. {storage} dahili depolama, pil sağlığı %{battery}. "
        f"Çizik yok, kılıf ve ekran koruyucu takılıydı. Kutusuyla birlikte, faturası mevcut."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": {"storage": storage},
    }

def _elektronik_laptop(idx: int) -> dict:
    brand   = pick(_LAPTOP["brands"])
    model   = pick(_LAPTOP["models"].get(brand, [brand + " Laptop"]))
    ram     = pick(_LAPTOP["ram"])
    storage = pick(_LAPTOP["storage"])
    price   = float(RNG.randint(*_LAPTOP["price_range"]))
    cpu     = "Apple M2" if brand == "Apple" else pick(["Intel Core i7", "Intel Core i5", "AMD Ryzen 7"])
    title   = f"{brand} {model} — {ram} RAM, {storage}"[:95]
    desc    = (
        f"{brand} {model} laptop satılıyorum. {ram} RAM, {storage}, {cpu} işlemci. "
        f"Hızlı performans, uzun pil ömrü. Kutusuyla birlikte, fatura dahil."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": {"ram": ram, "processor": cpu},
    }

def _elektronik_tablet(idx: int) -> dict:
    brands = {"Apple": ["iPad 10. Nesil", "iPad Air 5", "iPad Mini 6"],
              "Samsung": ["Galaxy Tab S8", "Galaxy Tab A8"],
              "Lenovo": ["Tab P12", "Tab M10 Plus"]}
    brand  = pick(list(brands.keys()))
    model  = pick(brands[brand])
    price  = float(RNG.randint(8_000, 45_000))
    title  = f"{brand} {model} tablet — az kullanılmış"[:95]
    desc   = (
        f"Satılık {brand} {model} tablet. Ekranında çizik bulunmuyor, "
        f"kalem varsa dahil. Seyahat ve iş kullanımı için ideal."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": None,
    }

def _elektronik_tv(idx: int) -> dict:
    brands = {"Samsung": ["55\" QLED 4K", "65\" Neo QLED", "43\" Crystal UHD"],
              "LG": ["55\" OLED C2", "65\" NanoCell", "43\" 4K UHD"],
              "Sony": ["55\" Bravia XR", "65\" A80K OLED"],
              "Beko": ["43\" Smart 4K", "55\" Smart"]}
    brand  = pick(list(brands.keys()))
    model  = pick(brands[brand])
    price  = float(RNG.randint(5_000, 60_000))
    title  = f"{brand} {model} — Smart TV, mükemmel görüntü"[:95]
    desc   = (
        f"{brand} {model} satılıyorum. Smart TV, Netflix ve YouTube uyumlu. "
        f"Uzaktan kumandası ve tüm kabloları dahil, sorunsuz çalışıyor."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": None,
    }

def _elektronik_konsol(idx: int) -> dict:
    brands = {"Sony":      ["PlayStation 5", "PlayStation 4 Pro"],
              "Microsoft": ["Xbox Series X", "Xbox Series S"],
              "Nintendo":  ["Switch OLED", "Switch Lite"]}
    brand  = pick(list(brands.keys()))
    model  = pick(brands[brand])
    price  = float(RNG.randint(5_000, 25_000))
    title  = f"{brand} {model} oyun konsolu"[:95]
    desc   = (
        f"{brand} {model} satılıyorum. Kutusunda, tüm aksesuarlar dahil. "
        f"Sorunsuz çalışıyor, üzerine oyun yüklenebilir."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["like_new", "used"]),
        "extra_fields": None,
    }

def _giyim_kadin(idx: int) -> dict:
    brand  = pick(_KADIN_GIYIM_BRANDS)
    types  = ["elbise", "bluz", "pantolon", "mont", "kazak"]
    tip    = pick(types)
    bedenler = ["XS", "S", "M", "L", "XL"]
    beden  = pick(bedenler)
    price  = float(RNG.randint(150, 3_000))
    title  = f"Kadın {tip} — {brand}, beden {beden}"[:95]
    desc   = (
        f"{brand} kadın {tip} satılıyorum. Beden {beden}, az giyilmiş, leke ve yıpranma yok. "
        f"Fiyat görüşülür."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _giyim_erkek(idx: int) -> dict:
    brand  = pick(_ERKEK_GIYIM_BRANDS)
    types  = ["gömlek", "tişört", "pantolon", "mont", "sweatshirt"]
    tip    = pick(types)
    bedenler = ["S", "M", "L", "XL", "XXL"]
    beden  = pick(bedenler)
    price  = float(RNG.randint(150, 2_500))
    title  = f"Erkek {tip} — {brand}, beden {beden}"[:95]
    desc   = (
        f"{brand} erkek {tip} satılıyorum. Beden {beden}, temiz kullanılmış. "
        f"Birkaç kez giyilmiş, ütülenmiş ve temiz."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _giyim_ayakkabi(idx: int) -> dict:
    brand  = pick(_AYAKKABI_BRANDS)
    model  = pick(_AYAKKABI_MODELS.get(brand, [brand + " Spor"]))
    numara = pick(["38", "39", "40", "41", "42", "43", "44"])
    price  = float(RNG.randint(500, 8_000))
    title  = f"{brand} {model} — numara {numara}"[:95]
    desc   = (
        f"{brand} {model} spor ayakkabı satılıyorum. Numara {numara}, kutusuyla birlikte. "
        f"Çok az kullanılmış, taban yıpranması yok."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _giyim_canta(idx: int) -> dict:
    brands = ["Zara", "Koton", "Michael Kors", "Louis Vuitton", "Tommy Hilfiger"]
    brand  = pick(brands)
    types  = ["omuz çantası", "sırt çantası", "el çantası", "valiz"]
    tip    = pick(types)
    price  = float(RNG.randint(400, 15_000))
    title  = f"Satılık {brand} {tip}"[:95]
    desc   = (
        f"{brand} {tip} satılıyorum. Orijinal ürün, az kullanılmış. "
        f"İç astarı temiz, fermuar ve aksamlar sorunsuz çalışıyor."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _giyim_saat(idx: int) -> dict:
    brand  = pick(_SAAT_BRANDS)
    model  = pick(_SAAT_MODELS.get(brand, [brand + " Classic"]))
    price  = float(RNG.randint(1_500, 50_000))
    title  = f"{brand} {model} kol saati"[:95]
    desc   = (
        f"{brand} {model} satılıyorum. Tertemiz, tüm işlevleri çalışıyor. "
        f"Kasa ve kayış hasar yok, orijinal kutusu mevcut."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _ev_mobilya(idx: int) -> dict:
    brands = ["İkea", "Bellona", "İstikbal", "Doğtaş", "Mondi"]
    brand  = pick(brands)
    types  = ["koltuk takımı", "yemek masası seti", "tv ünitesi", "kitaplık", "çalışma masası"]
    tip    = pick(types)
    price  = float(RNG.randint(800, 25_000))
    title  = f"Satılık {brand} {tip}"[:95]
    desc   = (
        f"{brand} {tip} satılıyorum. Taşınma nedeniyle elden çıkarıyorum. "
        f"Az kullanılmış, herhangi bir hasar veya çizik yok. Demontaj alıcıya aittir."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _ev_mutfak(idx: int) -> dict:
    brands = ["Tefal", "Korkmaz", "Arçelik", "Fakir", "Karaca"]
    brand  = pick(brands)
    items  = ["tencere seti", "kahve makinesi", "blender", "fırın", "fritöz"]
    item   = pick(items)
    price  = float(RNG.randint(300, 6_000))
    title  = f"{brand} {item} — az kullanılmış"[:95]
    desc   = (
        f"{brand} {item} satılıyorum. Sorunsuz çalışıyor, temiz kullanılmış. "
        f"Fiyatı makul, pazarlık payı var."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _ev_tekstil(idx: int) -> dict:
    brands = ["Madame Coco", "English Home", "Taç", "Özdilek", "Linens"]
    brand  = pick(brands)
    items  = ["nevresim takımı", "yorgan", "battaniye", "havlu seti", "halı"]
    item   = pick(items)
    price  = float(RNG.randint(300, 3_500))
    title  = f"{brand} {item}"[:95]
    desc   = (
        f"{brand} {item} satılıyorum. Çift kişilik, pamuklu. "
        f"Az kullanılmış veya sıfır, temiz."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _ev_dekor(idx: int) -> dict:
    items = [("Philips", "LED Avize"), ("Osram", "Akıllı Ampul Seti"),
             ("Vestel", "Sütun Lamba"), ("IKEA", "Dekoratif Aydınlatma")]
    brand, model = pick(items)
    price = float(RNG.randint(300, 6_000))
    title = f"{brand} {model} — satılık"[:95]
    desc  = (
        f"{brand} {model} satılıyorum. Modern tasarım, az kullanılmış veya sıfır. "
        f"Dekorasyonunuzu tazelemek için ideal."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _spor_bisiklet(idx: int) -> dict:
    brand = pick(_BISIKLET_BRANDS)
    model = pick(_BISIKLET_MODELS.get(brand, [brand + " Trekking"]))
    types = ["Dağ Bisikleti", "Şehir Bisikleti", "Yol Bisikleti"]
    tip   = pick(types)
    price = float(RNG.randint(3_000, 30_000))
    title = f"{brand} {model} — {tip}"[:95]
    desc  = (
        f"{brand} {model} {tip.lower()} satılıyorum. Az kullanılmış, tüm vitesleri çalışıyor. "
        f"Kask dahil, bakımı yapılmış. Şehir içi ve parkur sürüşü için uygun."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _spor_fitness(idx: int) -> dict:
    items = [
        ("Decathlon", "Koşu Bandı", 2_000, 15_000),
        ("Technogym", "Kondisyon Bisikleti", 3_000, 20_000),
        ("Life Fitness", "Eliptik Bisiklet", 4_000, 25_000),
        ("Kettler", "Ağırlık Seti", 1_000, 8_000),
        ("Decathlon", "Halter Seti", 500, 4_000),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} — ev tipi"[:95]
    desc  = (
        f"Satılık {brand} {model}. Evde az kullanılmış, sorunsuz çalışıyor. "
        f"Nakliye alıcıya aittir, kurulum konusunda yardımcı olunur."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _spor_outdoor(idx: int) -> dict:
    items = [
        ("Quechua", "Kamp Çadırı 2 Kişilik", 1_500, 6_000),
        ("The North Face", "Uyku Tulumu", 2_000, 8_000),
        ("Columbia", "Sırt Çantası 30L", 1_000, 4_000),
        ("Decathlon", "Trekking Botu", 500, 3_000),
        ("Mammut", "Outdoor Kıyafet Seti", 1_500, 7_000),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} — az kullanılmış"[:95]
    desc  = (
        f"{brand} {model} satılıyorum. Dağ yürüyüşü ve kamp için kullanılmış. "
        f"Az kullanılmış, su geçirmazlık özelliği korunmuş."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _spor_takim(idx: int) -> dict:
    items = [
        ("Nike", "Futbol Topu Profesyonel", 300, 1_500),
        ("Adidas", "Basketbol Topu", 400, 2_000),
        ("Wilson", "Tenis Raketi", 800, 5_000),
        ("Puma", "Futbol Krampon", 500, 3_000),
        ("Decathlon", "Badminton Seti", 300, 1_200),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} satılık"[:95]
    desc  = (
        f"{brand} {model} satılıyorum. Az kullanılmış, temiz. "
        f"Profesyonel kalite, fiyat görüşülür."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _kitap_roman(idx: int) -> dict:
    yayinevleri = ["İş Bankası Yayınları", "Can Yayınları", "Doğan Kitap", "YKY", "Epsilon"]
    yayinevi = pick(yayinevleri)
    titles_list = ["Türk edebiyatı romanlar seti", "Yerli çeviri karma kitaplar",
                   "Çok okunan bestseller kitaplar", "Klasik edebiyat seti"]
    kitap_title = pick(titles_list)
    price = float(RNG.randint(50, 600))
    title = f"{kitap_title} — {yayinevi}"[:95]
    desc  = (
        f"{yayinevi} çeşitli romanlar satılıyorum. Az okunmuş, temiz. "
        f"Tüm kitaplar birlikte ya da ayrı ayrı satılır."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": yayinevi, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _kitap_muzik(idx: int) -> dict:
    items = [
        ("Fender", "Akustik Gitar + Çanta", 2_000, 12_000),
        ("Yamaha", "Klasik Gitar", 1_500, 8_000),
        ("Roland", "Dijital Piyano 88 Tuş", 8_000, 30_000),
        ("Ibanez", "Elektro Gitar Seti", 3_000, 15_000),
        ("Gibson", "Ukulele", 1_000, 5_000),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} — satılık"[:95]
    desc  = (
        f"{brand} {model} satılıyorum. Çantasıyla birlikte, az kullanılmış. "
        f"Perde değişimi yakın zamanda yapıldı, ton mükemmel."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _kitap_koleksiyon(idx: int) -> dict:
    items = [
        "Eski pul koleksiyonu — çeşitli dönemler",
        "Antika bakır kaplar koleksiyonu",
        "Futbol forma koleksiyonu satılık",
        "Osmanlı dönemi antika ürünler",
        "Koleksiyon madeni paralar",
    ]
    item  = pick(items)
    price = float(RNG.randint(200, 8_000))
    title = item[:95]
    desc  = (
        f"Koleksiyon parçaları satılıyorum. Yıllarca özenle biriktirilen, iyi korunan parçalar. "
        f"Fiyatlar görüşülür, paket halinde indirim yapılır."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": pick(["like_new", "used"]),
        "extra_fields": None,
    }

def _kitap_ders(idx: int) -> dict:
    yayinevleri = ["Palme", "Nobel", "Seçkin", "Pegem", "Beta"]
    yayinevi = pick(yayinevleri)
    konular  = ["Hukuk", "Mühendislik", "Matematik", "Tıp", "YKS Kaynak", "KPSS Kaynak"]
    konu     = pick(konular)
    price    = float(RNG.randint(80, 1_000))
    title    = f"{konu} ders kitapları — {yayinevi}"[:95]
    desc     = (
        f"{konu} ders kitapları az kullanılmış. {yayinevi} baskı. "
        f"Üzerinde çok az kalem notu var, genel olarak temiz."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": yayinevi, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _diger_evcil(idx: int) -> dict:
    items = [
        ("Kedi evi ve oyuncak seti", 300, 2_500),
        ("Köpek koşum takımı ve gezdirme ipi", 200, 1_200),
        ("Kedi tırmalama tahtası + yatağı", 300, 1_800),
        ("Evcil hayvan taşıma çantası", 400, 2_000),
        ("Kuş kafesi — büyük boy", 500, 3_000),
    ]
    item, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{item}"[:95]
    desc  = (
        f"Evcil hayvan malzemesi satılıyorum: {item.lower()}. "
        f"Az kullanılmış veya sıfır, temiz. Hayvanımı kaybettiğim için satıyorum."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": None, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _diger_oyuncak(idx: int) -> dict:
    brands = ["Lego", "Fisher-Price", "Barbie", "Hot Wheels", "Playmobil"]
    brand  = pick(brands)
    items  = ["oyun seti", "figür koleksiyonu", "eğitici oyuncak", "araba seti"]
    item   = pick(items)
    price  = float(RNG.randint(150, 2_500))
    title  = f"{brand} {item} — çocuk oyuncağı"[:95]
    desc   = (
        f"{brand} {item} satılıyorum. Çocuğum büyüdü, kullanılmıyor. "
        f"Temiz ve eksiksiz, tüm parçaları mevcut."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": None,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }

def _diger_saglik(idx: int) -> dict:
    items = [
        ("Philips", "Saç düzleştirici", 800, 4_000),
        ("Dyson", "Saç kurutma makinesi", 3_000, 12_000),
        ("Braun", "Elektrikli tıraş makinesi", 500, 3_000),
        ("Philips", "Epilasyon cihazı", 1_000, 5_000),
        ("Omron", "Tansiyon aleti dijital", 400, 1_500),
    ]
    brand, model, pmin, pmax = pick(items)
    price = float(RNG.randint(pmin, pmax))
    title = f"{brand} {model} — az kullanılmış"[:95]
    desc  = (
        f"{brand} {model} satılıyorum. Az kullanılmış, sorunsuz çalışıyor. "
        f"Orijinal kutusu mevcut, fatura var."
    )
    return {
        "title": title, "description": desc, "price": price,
        "brand": brand, "model_name": model,
        "condition": pick(["new", "like_new", "used"]),
        "extra_fields": None,
    }


SUBCAT_MAKERS = {
    ("vasita", "otomobil"):            _vasita_otomobil,
    ("vasita", "motosiklet"):          _vasita_motosiklet,
    ("vasita", "elektrikli-arac"):     _vasita_elektrikli,
    ("vasita", "kamyonet-minibus"):    _vasita_kamyonet,
    ("vasita", "vasita-yedek-parca"): _vasita_parca,
    ("elektronik", "cep-telefonu"):   _elektronik_cep,
    ("elektronik", "bilgisayar-laptop"): _elektronik_laptop,
    ("elektronik", "tablet"):         _elektronik_tablet,
    ("elektronik", "tv-monitor"):     _elektronik_tv,
    ("elektronik", "oyun-konsolu"):   _elektronik_konsol,
    ("giyim-aksesuar", "kadin-giyim"): _giyim_kadin,
    ("giyim-aksesuar", "erkek-giyim"): _giyim_erkek,
    ("giyim-aksesuar", "ayakkabi"):   _giyim_ayakkabi,
    ("giyim-aksesuar", "canta-cuzdan"): _giyim_canta,
    ("giyim-aksesuar", "saat"):       _giyim_saat,
    ("ev-yasam", "mobilya"):          _ev_mobilya,
    ("ev-yasam", "mutfak-pisirme"):   _ev_mutfak,
    ("ev-yasam", "ev-tekstili"):      _ev_tekstil,
    ("ev-yasam", "dekorasyon-aydinlatma"): _ev_dekor,
    ("spor-outdoor", "bisiklet"):     _spor_bisiklet,
    ("spor-outdoor", "fitness-spor-salonu"): _spor_fitness,
    ("spor-outdoor", "outdoor-kamp"): _spor_outdoor,
    ("spor-outdoor", "takim-sporlari"): _spor_takim,
    ("kitap-hobi", "roman-hikaye"):   _kitap_roman,
    ("kitap-hobi", "muzik-aleti"):    _kitap_muzik,
    ("kitap-hobi", "koleksiyon"):     _kitap_koleksiyon,
    ("kitap-hobi", "ders-kitabi-akademik"): _kitap_ders,
    ("diger", "evcil-hayvan"):        _diger_evcil,
    ("diger", "oyuncak-cocuk-oyun"): _diger_oyuncak,
    ("diger", "saglik-guzellik"):     _diger_saglik,
}

def _emlak_maker(idx: int, subcat: str, province: str, district: str) -> dict:
    fn = {
        "daire":             _emlak_daire,
        "mustakil-ev-villa": _emlak_villa,
        "arsa":              _emlak_arsa,
        "is-yeri-ofis":      _emlak_isyeri,
    }.get(subcat, _emlak_daire)
    return fn(idx, province, district)


# ── Kategori Dağılımı ─────────────────────────────────────────────────────────

CAT_SUBCAT_WEIGHTS = {
    "vasita":         [("otomobil", 55), ("motosiklet", 20), ("elektrikli-arac", 10),
                       ("kamyonet-minibus", 10), ("vasita-yedek-parca", 5)],
    "emlak":          [("daire", 55), ("mustakil-ev-villa", 25), ("arsa", 12), ("is-yeri-ofis", 8)],
    "elektronik":     [("cep-telefonu", 40), ("bilgisayar-laptop", 30), ("tablet", 12),
                       ("tv-monitor", 10), ("oyun-konsolu", 8)],
    "giyim-aksesuar": [("kadin-giyim", 30), ("erkek-giyim", 25), ("ayakkabi", 20),
                       ("canta-cuzdan", 15), ("saat", 10)],
    "ev-yasam":       [("mobilya", 35), ("mutfak-pisirme", 25), ("ev-tekstili", 25),
                       ("dekorasyon-aydinlatma", 15)],
    "spor-outdoor":   [("bisiklet", 30), ("fitness-spor-salonu", 25), ("outdoor-kamp", 25),
                       ("takim-sporlari", 20)],
    "kitap-hobi":     [("roman-hikaye", 30), ("muzik-aleti", 25), ("koleksiyon", 25),
                       ("ders-kitabi-akademik", 20)],
    "diger":          [("evcil-hayvan", 40), ("oyuncak-cocuk-oyun", 35), ("saglik-guzellik", 25)],
}

GROUP_CAT_PROFILE = {
    "A": [("vasita", 70), ("elektronik", 15), ("ev-yasam", 10), ("diger", 5)],
    "B": [("emlak", 70), ("ev-yasam", 20), ("diger", 10)],
    "C": [("elektronik", 70), ("kitap-hobi", 15), ("giyim-aksesuar", 10), ("diger", 5)],
    "D": [("giyim-aksesuar", 45), ("spor-outdoor", 40), ("ev-yasam", 10), ("diger", 5)],
    "E": [("vasita", 12), ("emlak", 13), ("elektronik", 15), ("giyim-aksesuar", 15),
          ("ev-yasam", 15), ("spor-outdoor", 14), ("kitap-hobi", 10), ("diger", 6)],
}

def _pick_cat(gk: str) -> str:
    profile = GROUP_CAT_PROFILE[gk]
    cats, ws = zip(*profile)
    return wpick(list(cats), list(ws))

def _pick_subcat(cat: str) -> str:
    dist = CAT_SUBCAT_WEIGHTS[cat]
    subcats, ws = zip(*dist)
    return wpick(list(subcats), list(ws))


# ── JSON Üreticiler ──────────────────────────────────────────────────────────

def generate_listings() -> list[dict]:
    print("  generating mock_01_listings.json ...")
    listings = []
    idx = 0
    for gk, gv in GROUPS.items():
        for uid in gv["user_ids"]:
            for _ in range(12):
                cat    = _pick_cat(gk)
                subcat = _pick_subcat(cat)
                loc    = pick(LOCATIONS)
                province, district = loc
                location = f"{province}, {district}"
                ts = fmt(rand_dt(1, 90))
                imgs = [img(cat, idx), img(cat, idx, "b"), img(cat, idx, "c")]

                # Category-specific fields
                if cat == "emlak":
                    specific = _emlak_maker(idx, subcat, province, district)
                else:
                    maker = SUBCAT_MAKERS.get((cat, subcat))
                    if maker is None:
                        maker = SUBCAT_MAKERS.get((cat, CATEGORIES[cat][0]),
                                 list(SUBCAT_MAKERS.values())[0])
                    specific = maker(idx)

                # quality_score estimate
                q = 0.50
                if len(specific.get("description", "")) > 80: q += 0.10
                if specific.get("price"):    q += 0.10
                if specific.get("brand"):    q += 0.05
                if specific.get("model_name"): q += 0.05
                if specific.get("extra_fields"): q += 0.10
                q = round(min(q + RNG.uniform(-0.04, 0.04), 1.0), 4)

                listing = {
                    "listing_idx": idx,
                    "user_id": uid,
                    "category": cat,
                    "subcategory": subcat,
                    "province": province,
                    "district": district,
                    "location": location,
                    "image_url": imgs[0],
                    "image_urls": json.dumps(imgs),
                    "status": "active",
                    "created_at": ts,
                    "quality_score": q,
                    **specific,
                }
                listings.append(listing)
                idx += 1

    print(f"    ✓ {len(listings)} listing")
    return listings


INTERACTION_TYPES = [
    ("listing_impression",  0.3,  (1, 3)),
    ("listing_view",        1.0,  (10, 60)),
    ("listing_like",        3.0,  (5, 30)),
    ("listing_favorite",    5.0,  (15, 60)),
    ("listing_chat_open",   6.0,  (30, 180)),
    ("listing_offer_submit",10.0, (60, 300)),
    ("detail_dwell",        2.0,  (30, 120)),
]

def _pick_interaction() -> tuple[str, tuple]:
    itypes = [(t[0], t[2]) for t in INTERACTION_TYPES]
    # inverse weight: lighter events more frequent
    ws = [1.0 / max(t[1], 0.5) for t in INTERACTION_TYPES]
    chosen = wpick(itypes, ws)
    return chosen[0], chosen[1]


def generate_user_interactions(listings: list[dict]) -> list[dict]:
    print("  generating mock_02_user_interactions.json ...")
    listing_meta = {l["listing_idx"]: (l["category"], l["user_id"]) for l in listings}
    all_idx = list(listing_meta.keys())
    events: list[dict] = []

    for uid in ALL_USER_IDS:
        gk  = USER_GROUP[uid]
        grp = GROUPS[gk]
        primary_cat = grp["primary_cat"]

        if gk == "E":
            n = RNG.randint(5, 9)
            sample = RNG.choices(all_idx, k=n)
        else:
            n_total = RNG.randint(85, 120)
            own_ids = {l["listing_idx"] for l in listings if l["user_id"] == uid}
            primary  = [i for i in all_idx if listing_meta[i][0] == primary_cat  and i not in own_ids]
            others   = [i for i in all_idx if listing_meta[i][0] != primary_cat  and i not in own_ids]
            n_prim   = int(n_total * 0.70)
            n_other  = n_total - n_prim
            prim_s   = RNG.choices(primary, k=min(n_prim, len(primary))) if primary else []
            other_s  = RNG.choices(others,  k=min(n_other, len(others)))  if others  else []
            sample   = (prim_s + other_s)[:n_total]

        for li in sample:
            itype, dur_range = _pick_interaction()
            events.append({
                "user_id": uid,
                "listing_idx": li,
                "item_type": "listing",
                "interaction_type": itype,
                "duration_seconds": round(RNG.uniform(*dur_range), 1),
                "created_at": fmt(recent_ts(120)),
            })

    RNG.shuffle(events)
    print(f"    ✓ {len(events)} interactions")
    return events


def generate_user_interests() -> list[dict]:
    print("  generating mock_03_user_interests.json ...")
    # One row per (user_id, category) — UniqueConstraint("user_id", "category")
    templates: dict[str, list] = {
        "A": [
            ("vasita",         "otomobil",       0.85),
            ("elektronik",     "cep-telefonu",   0.28),
            ("ev-yasam",       None,             0.18),
            ("giyim-aksesuar", None,             0.12),
            ("spor-outdoor",   None,             0.08),
        ],
        "B": [
            ("emlak",          "daire",          0.82),
            ("ev-yasam",       "mobilya",        0.44),
            ("giyim-aksesuar", None,             0.18),
            ("vasita",         None,             0.14),
            ("kitap-hobi",     None,             0.09),
        ],
        "C": [
            ("elektronik",     "cep-telefonu",   0.80),
            ("kitap-hobi",     "muzik-aleti",    0.33),
            ("giyim-aksesuar", None,             0.18),
            ("spor-outdoor",   None,             0.14),
            ("ev-yasam",       None,             0.09),
        ],
        "D": [
            ("giyim-aksesuar", "kadin-giyim",   0.65),
            ("spor-outdoor",   "bisiklet",       0.54),
            ("ev-yasam",       None,             0.22),
            ("elektronik",     None,             0.16),
            ("diger",          None,             0.09),
        ],
        "E": [
            ("elektronik",     None,             0.14),
            ("giyim-aksesuar", None,             0.11),
            ("vasita",         None,             0.09),
        ],
    }
    rows: list[dict] = []
    for uid in ALL_USER_IDS:
        gk = USER_GROUP[uid]
        for cat, subcat, base in templates[gk]:
            score = round(max(0.05, min(1.0, base + RNG.uniform(-0.06, 0.06))), 4)
            rows.append({"user_id": uid, "category": cat, "subcategory": subcat, "score": score})

    print(f"    ✓ {len(rows)} user_interests")
    return rows


def generate_feed_analytics(listings: list[dict]) -> list[dict]:
    print("  generating mock_04_feed_analytics.json ...")
    listing_meta = {l["listing_idx"]: (l["category"], l["subcategory"], l.get("condition") or "")
                    for l in listings}
    all_idx = list(listing_meta.keys())
    rows: list[dict] = []

    for uid in ALL_USER_IDS:
        gk  = USER_GROUP[uid]
        primary_cat = GROUPS[gk]["primary_cat"]
        n = RNG.randint(48, 72) if gk != "E" else RNG.randint(12, 20)

        for _ in range(n):
            li = pick(all_idx)
            cat, subcat, cond = listing_meta[li]
            is_primary = (cat == primary_cat)

            if is_primary:
                etype = wpick(["click", "impression", "skip"], [0.50, 0.35, 0.15])
            else:
                etype = wpick(["click", "impression", "skip"], [0.15, 0.45, 0.40])

            dwell = (RNG.randint(5_000, 30_000) if etype == "click"
                     else RNG.randint(1_000, 8_000) if etype == "impression"
                     else RNG.randint(0, 500))

            rows.append({
                "timestamp":          fmt(recent_ts(30)),
                "user_id":            str(uid),
                "listing_idx":        li,
                "event_type":         etype,
                "dwell_time_ms":      dwell,
                "content_type":       "listing",
                "slot_index":         RNG.randint(0, 29),
                "stream_category":    "",
                "listing_condition":  cond,
                "listing_subcategory": subcat or "",
            })

    RNG.shuffle(rows)
    print(f"    ✓ {len(rows)} feed_analytics")
    return rows


_QUERIES = {
    "vasita":         [("sedan araba ikinci el", "otomobil"),
                       ("2020 dizel vw passat", "otomobil"),
                       ("motosiklet satılık honda", "motosiklet"),
                       ("elektrikli scooter", "elektrikli-arac"),
                       ("ticari araç ford transit", "kamyonet-minibus")],
    "emlak":          [("kiralık 2+1 daire istanbul", "daire"),
                       ("satılık müstakil ev bahçeli", "mustakil-ev-villa"),
                       ("arsa yatırım", "arsa"),
                       ("kiralık ofis izmir", "is-yeri-ofis"),
                       ("satılık daire ankara", "daire")],
    "elektronik":     [("iphone 15 satılık", "cep-telefonu"),
                       ("samsung galaxy s23", "cep-telefonu"),
                       ("macbook air m2", "bilgisayar-laptop"),
                       ("gaming laptop rtx", "bilgisayar-laptop"),
                       ("playstation 5 satılık", "oyun-konsolu")],
    "giyim-aksesuar": [("zara elbise beden m", "kadin-giyim"),
                       ("nike air force 1", "ayakkabi"),
                       ("erkek gömlek h&m", "erkek-giyim"),
                       ("casio g-shock saat", "saat"),
                       ("deri omuz çantası", "canta-cuzdan")],
    "spor-outdoor":   [("dağ bisikleti 29 jant", "bisiklet"),
                       ("koşu bandı satılık ev", "fitness-spor-salonu"),
                       ("kamp çadırı 2 kişilik", "outdoor-kamp"),
                       ("futbol topu profesyonel", "takim-sporlari")],
    "ev-yasam":       [("koltuk takımı satılık", "mobilya"),
                       ("tefal tencere seti", "mutfak-pisirme"),
                       ("nevresim takımı çift kişilik", "ev-tekstili")],
    "kitap-hobi":     [("roman kitap seti", "roman-hikaye"),
                       ("akustik gitar satılık fender", "muzik-aleti"),
                       ("ders kitabı üniversite", "ders-kitabi-akademik")],
    "diger":          [("kedi evi oyuncak", "evcil-hayvan"),
                       ("lego oyuncak seti", "oyuncak-cocuk-oyun"),
                       ("philips saç makinesi", "saglik-guzellik")],
}

def generate_search_events() -> list[dict]:
    print("  generating mock_05_search_events.json ...")
    rows: list[dict] = []

    for uid in ALL_USER_IDS:
        gk  = USER_GROUP[uid]
        primary_cat = GROUPS[gk]["primary_cat"]
        n = RNG.randint(8, 14) if gk != "E" else RNG.randint(3, 6)

        for _ in range(n):
            if primary_cat and RNG.random() < 0.70:
                cat_key = primary_cat
            else:
                cat_key = pick(list(_QUERIES.keys()))

            q_list  = _QUERIES.get(cat_key, _QUERIES["diger"])
            query, subcat = pick(q_list)
            cat     = cat_key if cat_key in CATEGORIES else pick(list(CATEGORIES.keys()))

            rows.append({
                "timestamp":    fmt(recent_ts(30)),
                "user_id":      uid,
                "query":        query,
                "category":     cat,
                "subcategory":  subcat or _pick_subcat(cat),
                "result_count": RNG.randint(5, 200),
                "intent":       pick(["browse", "buy", "compare"]),
            })

    RNG.shuffle(rows)
    print(f"    ✓ {len(rows)} search_events")
    return rows


def generate_swipe_live(listings: list[dict]) -> list[dict]:
    print("  generating mock_06_swipe_live.json ...")
    listing_meta = {l["listing_idx"]: (l["category"], l["subcategory"], l.get("condition") or "")
                    for l in listings}
    all_idx   = list(listing_meta.keys())
    stream_ids = list(range(4, 34))
    rows: list[dict] = []

    for uid in ALL_USER_IDS:
        gk  = USER_GROUP[uid]
        primary_cat = GROUPS[gk]["primary_cat"]
        n = RNG.randint(5, 8) if gk != "E" else RNG.randint(2, 4)

        for _ in range(n):
            sid  = pick(stream_ids)
            s_cat, s_subcat = STREAM_CATS.get(sid, ("diger", None))
            li   = pick(all_idx)
            l_cat, l_subcat, l_cond = listing_meta[li]
            is_match = (s_cat == primary_cat)

            if is_match:
                etype = wpick(["dwell", "skip", "stream_heart"], [0.55, 0.25, 0.20])
                dwell = RNG.randint(8_000, 60_000)
            else:
                etype = wpick(["dwell", "skip", "stream_heart"], [0.20, 0.65, 0.15])
                dwell = RNG.randint(500, 8_000)

            rows.append({
                "user_id":             uid,
                "stream_id":           sid,
                "listing_idx":         li,
                "event_type":          etype,
                "dwell_ms":            dwell,
                "stream_category":     s_cat,
                "stream_subcategory":  s_subcat or "",
                "listing_category":    l_cat,
                "listing_subcategory": l_subcat or "",
                "listing_condition":   l_cond,
                "listings_seen":       RNG.randint(1, 8),
                "slot_index":          RNG.randint(0, 15),
                "session_id":          f"mock_{uid}_{sid}",
                "timestamp":           fmt(recent_ts(30)),
            })

    RNG.shuffle(rows)
    print(f"    ✓ {len(rows)} swipe_live_events")
    return rows


# ── Ana Akış ──────────────────────────────────────────────────────────────────

def main() -> None:
    print("=== Teqlif Mock Data Generator (seed=42) ===\n")

    listings     = generate_listings()
    interactions = generate_user_interactions(listings)
    interests    = generate_user_interests()
    feed         = generate_feed_analytics(listings)
    search       = generate_search_events()
    swipe        = generate_swipe_live(listings)

    files = [
        ("mock_01_listings.json",           listings),
        ("mock_02_user_interactions.json",   interactions),
        ("mock_03_user_interests.json",      interests),
        ("mock_04_feed_analytics.json",      feed),
        ("mock_05_search_events.json",       search),
        ("mock_06_swipe_live.json",          swipe),
    ]

    print("\nYazılıyor...")
    for fname, data in files:
        path = OUT_DIR / fname
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        kb = path.stat().st_size // 1024
        print(f"  {fname:<42} {len(data):>5} satır   {kb:>5}KB")

    print("\n✅ Tüm mock veriler üretildi.")
    print(f"Dizin: {OUT_DIR}")
    print("\nSıradaki adım: T08 — insert scriptlerini yaz")


if __name__ == "__main__":
    main()
