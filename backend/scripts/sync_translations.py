"""
ARB dosyalarını ve opt_* option key'lerini translations tablosuna sync'ler.

Kullanım (VPS'te):
    cd /var/www/teqlif.com/backend
    source /var/www/teqlif.com/venv/bin/activate
    python scripts/sync_translations.py

Ne yapar:
  - mobile/lib/l10n/app_{tr,en,ar,ru}.arb dosyalarını okur
  - @-annotation ve @@locale satırlarını atlar
  - ARB'de bulunmayan opt_* option label'larını statik dict'ten ekler
  - translations tablosuna UPSERT eder (key, lang, value)
  - Redis i18n cache'ini invalidate eder
  - Kaç key sync'lendiğini raporlar
"""
import asyncio
import json
import os
import sys

from dotenv import load_dotenv

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)
load_dotenv(os.path.join(backend_dir, ".env"))

import sqlalchemy as sa
from sqlalchemy import ARRAY, Text, bindparam

from app.database import AsyncSessionLocal
from app.utils.redis_client import get_redis

_LANGS = ["tr", "en", "ar", "ru"]
_ARB_DIR = os.path.join(backend_dir, "..", "mobile", "lib", "l10n")

# opt_* keys are not in ARB files — maintained here as the single source of truth.
# Brand/model names, numeric specs (16GB, 35 shoe size, 11" screen) are NOT here;
# their DB label column already holds the correct universal display value.
# Format: key -> {lang: value}
_OPT_TRANSLATIONS: dict[str, dict[str, str]] = {
    # ── Colors ────────────────────────────────────────────────────────────────
    "opt_white":              {"tr": "Beyaz",                "en": "White",               "ar": "أبيض",                   "ru": "Белый"},
    "opt_gray":               {"tr": "Gri",                  "en": "Gray",                "ar": "رمادي",                  "ru": "Серый"},
    "opt_black":              {"tr": "Siyah",                "en": "Black",               "ar": "أسود",                   "ru": "Чёрный"},
    "opt_blue":               {"tr": "Mavi",                 "en": "Blue",                "ar": "أزرق",                   "ru": "Синий"},
    "opt_red":                {"tr": "Kırmızı",              "en": "Red",                 "ar": "أحمر",                   "ru": "Красный"},
    "opt_green":              {"tr": "Yeşil",                "en": "Green",               "ar": "أخضر",                   "ru": "Зелёный"},
    "opt_yellow":             {"tr": "Sarı",                 "en": "Yellow",              "ar": "أصفر",                   "ru": "Жёлтый"},
    "opt_orange":             {"tr": "Turuncu",              "en": "Orange",              "ar": "برتقالي",                "ru": "Оранжевый"},
    "opt_purple":             {"tr": "Mor",                  "en": "Purple",              "ar": "بنفسجي",                 "ru": "Фиолетовый"},
    "opt_pink":               {"tr": "Pembe",                "en": "Pink",                "ar": "وردي",                   "ru": "Розовый"},
    "opt_brown":              {"tr": "Kahverengi",           "en": "Brown",               "ar": "بني",                    "ru": "Коричневый"},
    "opt_beige":              {"tr": "Bej",                  "en": "Beige",               "ar": "بيج",                    "ru": "Бежевый"},
    "opt_gold":               {"tr": "Altın",                "en": "Gold",                "ar": "ذهبي",                   "ru": "Золотой"},
    "opt_silver":             {"tr": "Gümüş",                "en": "Silver",              "ar": "فضي",                    "ru": "Серебристый"},

    # ── Common ────────────────────────────────────────────────────────────────
    "opt_other":              {"tr": "Diğer",                "en": "Other",               "ar": "أخرى",                   "ru": "Другое"},
    "opt_yes":                {"tr": "Var",                  "en": "Yes",                 "ar": "نعم",                    "ru": "Да"},
    "opt_no":                 {"tr": "Yok",                  "en": "No",                  "ar": "لا",                     "ru": "Нет"},
    "opt_none":               {"tr": "Yok",                  "en": "None",                "ar": "لا يوجد",                "ru": "Нет"},

    # ── Fuel types ────────────────────────────────────────────────────────────
    "opt_gasoline":           {"tr": "Benzin",               "en": "Gasoline",            "ar": "بنزين",                  "ru": "Бензин"},
    "opt_diesel":             {"tr": "Dizel",                "en": "Diesel",              "ar": "ديزل",                   "ru": "Дизель"},
    "opt_lpg":                {"tr": "LPG",                  "en": "LPG",                 "ar": "غاز البترول المسال",     "ru": "СНГ"},
    "opt_hybrid":             {"tr": "Hibrit",               "en": "Hybrid",              "ar": "هجين",                   "ru": "Гибрид"},
    "opt_electric":           {"tr": "Elektrik",             "en": "Electric",            "ar": "كهربائي",                "ru": "Электрический"},
    "opt_sail":               {"tr": "Yelken",               "en": "Sail",                "ar": "شراع",                   "ru": "Парус"},

    # ── Transmission ─────────────────────────────────────────────────────────
    "opt_manual":             {"tr": "Manuel",               "en": "Manual",              "ar": "يدوي",                   "ru": "Ручная"},
    "opt_automatic":          {"tr": "Otomatik",             "en": "Automatic",           "ar": "أوتوماتيك",              "ru": "Автомат"},
    "opt_semi_automatic":     {"tr": "Yarı Otomatik",        "en": "Semi-Automatic",      "ar": "نصف أوتوماتيك",          "ru": "Полуавтомат"},

    # ── Body types ────────────────────────────────────────────────────────────
    "opt_sedan":              {"tr": "Sedan",                "en": "Sedan",               "ar": "سيدان",                  "ru": "Седан"},
    "opt_hatchback":          {"tr": "Hatchback",            "en": "Hatchback",           "ar": "هاتشباك",                "ru": "Хэтчбек"},
    "opt_suv":                {"tr": "SUV",                  "en": "SUV",                 "ar": "سيارة دفع رباعي",        "ru": "Внедорожник"},
    "opt_station_wagon":      {"tr": "Station Wagon",        "en": "Station Wagon",       "ar": "ستيشن واجن",             "ru": "Универсал"},
    "opt_coupe":              {"tr": "Coupe",                "en": "Coupe",               "ar": "كوبيه",                  "ru": "Купе"},
    "opt_cabriolet":          {"tr": "Cabriolet",            "en": "Cabriolet",           "ar": "كابريوليه",              "ru": "Кабриолет"},
    "opt_pickup":             {"tr": "Pickup",               "en": "Pickup",              "ar": "بيكاب",                  "ru": "Пикап"},
    "opt_van":                {"tr": "Van",                  "en": "Van",                 "ar": "فان",                    "ru": "Фургон"},
    "opt_minibus":            {"tr": "Minibüs",              "en": "Minibus",             "ar": "ميني باص",               "ru": "Микроавтобус"},

    # ── Motorcycle types ──────────────────────────────────────────────────────
    "opt_naked":              {"tr": "Naked",                "en": "Naked",               "ar": "نيكد",                   "ru": "Нейкед"},
    "opt_sport":              {"tr": "Sport",                "en": "Sport",               "ar": "رياضي",                  "ru": "Спортивный"},
    "opt_touring":            {"tr": "Touring",              "en": "Touring",             "ar": "سياحي",                  "ru": "Туристический"},
    "opt_enduro":             {"tr": "Enduro",               "en": "Enduro",              "ar": "إندورو",                 "ru": "Эндуро"},
    "opt_scooter":            {"tr": "Scooter",              "en": "Scooter",             "ar": "سكوتر",                  "ru": "Скутер"},
    "opt_chopper":            {"tr": "Chopper",              "en": "Chopper",             "ar": "شوبر",                   "ru": "Чоппер"},
    "opt_adventure":          {"tr": "Adventure",            "en": "Adventure",           "ar": "مغامرة",                 "ru": "Туристический/Эндуро"},

    # ── Damage status ─────────────────────────────────────────────────────────
    "opt_painted":            {"tr": "Boyalı",               "en": "Painted",             "ar": "مطلي",                   "ru": "Крашеный"},
    "opt_accident":           {"tr": "Kazalı",               "en": "Accident History",    "ar": "تاريخ حوادث",            "ru": "Побывал в аварии"},
    "opt_damage_record":      {"tr": "Hasar Kayıtlı",        "en": "Damage Record",       "ar": "سجل الأضرار",            "ru": "Есть записи о повреждениях"},
    "opt_heavy_damage_record":{"tr": "Ağır Hasar Kayıtlı",  "en": "Heavy Damage Record", "ar": "أضرار جسيمة",            "ru": "Тяжёлые повреждения"},
    "opt_flawless":           {"tr": "Hatasız",              "en": "Flawless",            "ar": "بلا عيوب",               "ru": "Без дефектов"},

    # ── Boat types ────────────────────────────────────────────────────────────
    "opt_motorboat":          {"tr": "Motor Tekne",          "en": "Motorboat",           "ar": "قارب محرك",              "ru": "Моторная лодка"},
    "opt_sailboat":           {"tr": "Yelkenli",             "en": "Sailboat",            "ar": "قارب شراعي",             "ru": "Парусная яхта"},
    "opt_speedboat":          {"tr": "Sürat Teknesi",        "en": "Speedboat",           "ar": "قارب سريع",              "ru": "Скоростной катер"},
    "opt_cutter":             {"tr": "Kotra",                "en": "Cutter",              "ar": "كوتر",                   "ru": "Катер"},
    "opt_kayak":              {"tr": "Kanotaj / Kayak",      "en": "Kayak",               "ar": "كاياك",                  "ru": "Каяк"},
    "opt_jet_ski":            {"tr": "Jet Ski",              "en": "Jet Ski",             "ar": "جت سكي",                 "ru": "Гидроцикл"},

    # ── Camera types ──────────────────────────────────────────────────────────
    "opt_dslr":               {"tr": "DSLR",                 "en": "DSLR",                "ar": "DSLR",                   "ru": "DSLR"},
    "opt_mirrorless":         {"tr": "Mirrorless",           "en": "Mirrorless",          "ar": "ميرورليس",               "ru": "Беззеркальный"},
    "opt_compact":            {"tr": "Kompakt",              "en": "Compact",             "ar": "مدمج",                   "ru": "Компактный"},
    "opt_action":             {"tr": "Action Kamera",        "en": "Action Camera",       "ar": "كاميرا أكشن",            "ru": "Экшн-камера"},
    "opt_video":              {"tr": "Video Kamera",         "en": "Camcorder",           "ar": "كاميرا فيديو",           "ru": "Видеокамера"},

    # ── Photo equipment ───────────────────────────────────────────────────────
    "opt_camera":             {"tr": "Kamera",               "en": "Camera",              "ar": "كاميرا",                 "ru": "Камера"},
    "opt_lens":               {"tr": "Lens",                 "en": "Lens",                "ar": "عدسة",                   "ru": "Объектив"},
    "opt_tripod":             {"tr": "Tripod",               "en": "Tripod",              "ar": "حامل ثلاثي",             "ru": "Штатив"},
    "opt_drone":              {"tr": "Drone",                "en": "Drone",               "ar": "طائرة مسيّرة",           "ru": "Дрон"},
    "opt_flash":              {"tr": "Flaş / Işık",          "en": "Flash / Light",       "ar": "فلاش / إضاءة",           "ru": "Вспышка / Свет"},

    # ── Real estate — Room count ──────────────────────────────────────────────
    "opt_1+0":                {"tr": "1+0 Stüdyo",          "en": "Studio (1+0)",        "ar": "1+0 استوديو",            "ru": "Студия (1+0)"},
    "opt_6+1":                {"tr": "6+1 ve üzeri",        "en": "6+1 and above",       "ar": "6+1 وأكثر",              "ru": "6+1 и выше"},

    # ── Real estate — Building age ────────────────────────────────────────────
    "opt_new_build":          {"tr": "Sıfır (0 Yıl)",       "en": "New Build",           "ar": "مبنى جديد",              "ru": "Новостройка"},
    "opt_1_5":                {"tr": "1–5 Yıl",             "en": "1–5 Years",           "ar": "1–5 سنوات",              "ru": "1–5 лет"},
    "opt_6_10":               {"tr": "6–10 Yıl",            "en": "6–10 Years",          "ar": "6–10 سنوات",             "ru": "6–10 лет"},
    "opt_11_15":              {"tr": "11–15 Yıl",           "en": "11–15 Years",         "ar": "11–15 سنة",              "ru": "11–15 лет"},
    "opt_16_20":              {"tr": "16–20 Yıl",           "en": "16–20 Years",         "ar": "16–20 سنة",              "ru": "16–20 лет"},
    "opt_21_plus":            {"tr": "21 Yıl ve Üzeri",     "en": "21+ Years",           "ar": "21 سنة وأكثر",           "ru": "21 год и более"},

    # ── Real estate — Heating ─────────────────────────────────────────────────
    "opt_combi_boiler":       {"tr": "Kombi",               "en": "Combi Boiler",        "ar": "غلاية مركبة",            "ru": "Газовый котёл (комби)"},
    "opt_central_gas":        {"tr": "Doğalgaz (Merkezi)",  "en": "Central Gas Heating", "ar": "غاز مركزي",              "ru": "Центральное газовое"},
    "opt_stove":              {"tr": "Soba",                 "en": "Stove",               "ar": "موقد",                   "ru": "Печь"},
    "opt_air_conditioning":   {"tr": "Klima",               "en": "Air Conditioning",    "ar": "تكييف هواء",             "ru": "Кондиционер"},
    "opt_underfloor_heating": {"tr": "Yerden Isıtma",       "en": "Underfloor Heating",  "ar": "تدفئة تحت الأرضية",      "ru": "Тёплый пол"},

    # ── Real estate — Furnished ───────────────────────────────────────────────
    "opt_furnished":          {"tr": "Eşyalı",              "en": "Furnished",           "ar": "مؤثث",                   "ru": "С мебелью"},
    "opt_semi_furnished":     {"tr": "Yarı Eşyalı",         "en": "Semi-Furnished",      "ar": "مؤثث جزئياً",            "ru": "Частично с мебелью"},
    "opt_empty":              {"tr": "Boş",                  "en": "Unfurnished",         "ar": "فارغ",                   "ru": "Без мебели"},

    # ── Real estate — Title deed ──────────────────────────────────────────────
    "opt_condominium":        {"tr": "Kat Mülkiyeti",       "en": "Condominium Title",   "ar": "ملكية الشقة",            "ru": "Право собственности"},
    "opt_floor_easement":     {"tr": "Kat İrtifakı",        "en": "Floor Easement",      "ar": "حق ارتفاق الطابق",       "ru": "Право пользования этажом"},
    "opt_shared_ownership":   {"tr": "Hisseli Tapu",        "en": "Shared Ownership",    "ar": "ملكية مشتركة",           "ru": "Долевая собственность"},
    "opt_land_title":         {"tr": "Arsa Tapusu",         "en": "Land Title",          "ar": "سند الأرض",              "ru": "Свидетельство на землю"},

    # ── Real estate — Land use ────────────────────────────────────────────────
    "opt_residential":        {"tr": "Konut İmarlı",        "en": "Residential",         "ar": "سكني",                   "ru": "Жилое"},
    "opt_commercial":         {"tr": "Ticari İmarlı",       "en": "Commercial",          "ar": "تجاري",                  "ru": "Коммерческое"},
    "opt_agricultural":       {"tr": "Tarımsal",            "en": "Agricultural",        "ar": "زراعي",                  "ru": "Сельскохозяйственное"},
    "opt_industrial":         {"tr": "Sanayi",              "en": "Industrial",          "ar": "صناعي",                  "ru": "Промышленное"},

    # ── Fashion — Shoe types ──────────────────────────────────────────────────
    "opt_sneaker":            {"tr": "Spor / Sneaker",      "en": "Sneaker",             "ar": "حذاء رياضي",             "ru": "Кроссовки"},
    "opt_formal":             {"tr": "Klasik",              "en": "Formal",              "ar": "رسمي",                   "ru": "Классические"},
    "opt_boot":               {"tr": "Bot",                 "en": "Boot",                "ar": "حذاء برقبة",             "ru": "Ботинки"},
    "opt_sandal":             {"tr": "Sandalet",            "en": "Sandal",              "ar": "صندل",                   "ru": "Сандалии"},
    "opt_slipper":            {"tr": "Terlik",              "en": "Slipper",             "ar": "شبشب",                   "ru": "Тапочки"},
    "opt_heeled":             {"tr": "Topuklu",             "en": "Heeled",              "ar": "بكعب",                   "ru": "На каблуке"},

    # ── Fashion — Materials ───────────────────────────────────────────────────
    "opt_leather":            {"tr": "Deri",                "en": "Leather",             "ar": "جلد",                    "ru": "Кожа"},
    "opt_faux_leather":       {"tr": "Suni Deri",           "en": "Faux Leather",        "ar": "جلد صناعي",              "ru": "Искусственная кожа"},
    "opt_fabric":             {"tr": "Kumaş",               "en": "Fabric",              "ar": "قماش",                   "ru": "Ткань"},
    "opt_canvas":             {"tr": "Kanvas",              "en": "Canvas",              "ar": "قماش كانفاس",            "ru": "Холст"},

    # ── Jewelry / precious metals ─────────────────────────────────────────────
    "opt_platinum":           {"tr": "Platin",              "en": "Platinum",            "ar": "بلاتين",                 "ru": "Платина"},
    "opt_diamond":            {"tr": "Elmas",               "en": "Diamond",             "ar": "ألماس",                  "ru": "Бриллиант"},
    "opt_natural_stone":      {"tr": "Doğal Taş",           "en": "Natural Stone",       "ar": "حجر طبيعي",              "ru": "Природный камень"},

    # ── Watch / gender ────────────────────────────────────────────────────────
    "opt_male":               {"tr": "Erkek",               "en": "Men's",               "ar": "رجالي",                  "ru": "Мужские"},
    "opt_female":             {"tr": "Kadın",               "en": "Women's",             "ar": "نسائي",                  "ru": "Женские"},
    "opt_unisex":             {"tr": "Unisex",              "en": "Unisex",              "ar": "للجنسين",                "ru": "Унисекс"},

    # ── Children's clothing sizes ─────────────────────────────────────────────
    "opt_0_3m":               {"tr": "0–3 Ay",              "en": "0–3 Months",          "ar": "0–3 أشهر",               "ru": "0–3 месяца"},
    "opt_3_6m":               {"tr": "3–6 Ay",              "en": "3–6 Months",          "ar": "3–6 أشهر",               "ru": "3–6 месяцев"},
    "opt_6_12m":              {"tr": "6–12 Ay",             "en": "6–12 Months",         "ar": "6–12 شهرًا",             "ru": "6–12 месяцев"},
    "opt_1_2y":               {"tr": "1–2 Yaş",             "en": "1–2 Years",           "ar": "1–2 سنة",                "ru": "1–2 года"},
    "opt_3_4y":               {"tr": "3–4 Yaş",             "en": "3–4 Years",           "ar": "3–4 سنوات",              "ru": "3–4 года"},
    "opt_5_6y":               {"tr": "5–6 Yaş",             "en": "5–6 Years",           "ar": "5–6 سنوات",              "ru": "5–6 лет"},
    "opt_7_8y":               {"tr": "7–8 Yaş",             "en": "7–8 Years",           "ar": "7–8 سنوات",              "ru": "7–8 лет"},
    "opt_9_10y":              {"tr": "9–10 Yaş",            "en": "9–10 Years",          "ar": "9–10 سنوات",             "ru": "9–10 лет"},
    "opt_11_12y":             {"tr": "11–12 Yaş",           "en": "11–12 Years",         "ar": "11–12 سنة",              "ru": "11–12 лет"},
    "opt_13_14y":             {"tr": "13–14 Yaş",           "en": "13–14 Years",         "ar": "13–14 سنة",              "ru": "13–14 лет"},

    # ── Furniture types ───────────────────────────────────────────────────────
    "opt_sofa":               {"tr": "Koltuk / Kanepe",     "en": "Sofa",                "ar": "أريكة",                  "ru": "Диван"},
    "opt_bed":                {"tr": "Yatak",               "en": "Bed",                 "ar": "سرير",                   "ru": "Кровать"},
    "opt_table":              {"tr": "Masa",                "en": "Table",               "ar": "طاولة",                  "ru": "Стол"},
    "opt_chair":              {"tr": "Sandalye",            "en": "Chair",               "ar": "كرسي",                   "ru": "Стул"},
    "opt_wardrobe":           {"tr": "Dolap / Gardırop",    "en": "Wardrobe",            "ar": "خزانة ملابس",            "ru": "Гардероб"},
    "opt_shelf":              {"tr": "Raf / Kitaplık",      "en": "Shelf / Bookcase",    "ar": "رف / مكتبة",             "ru": "Полка"},
    "opt_coffee_table":       {"tr": "Sehpa",               "en": "Coffee Table",        "ar": "طاولة قهوة",              "ru": "Журнальный столик"},

    # ── Furniture / home materials ────────────────────────────────────────────
    "opt_wood":               {"tr": "Ahşap",               "en": "Wood",                "ar": "خشب",                    "ru": "Дерево"},
    "opt_metal":              {"tr": "Metal",               "en": "Metal",               "ar": "معدن",                   "ru": "Металл"},
    "opt_plastic":            {"tr": "Plastik",             "en": "Plastic",             "ar": "بلاستيك",                "ru": "Пластик"},
    "opt_glass":              {"tr": "Cam",                 "en": "Glass",               "ar": "زجاج",                   "ru": "Стекло"},

    # ── Home textiles ─────────────────────────────────────────────────────────
    "opt_bedding_set":        {"tr": "Nevresim Takımı",     "en": "Bedding Set",         "ar": "طقم مفرش",               "ru": "Постельный комплект"},
    "opt_quilt":              {"tr": "Yorgan",              "en": "Quilt",               "ar": "لحاف",                   "ru": "Одеяло"},
    "opt_pillow":             {"tr": "Yastık",              "en": "Pillow",              "ar": "وسادة",                  "ru": "Подушка"},
    "opt_towel":              {"tr": "Havlu",               "en": "Towel",               "ar": "منشفة",                  "ru": "Полотенце"},
    "opt_curtain":            {"tr": "Perde",               "en": "Curtain",             "ar": "ستارة",                  "ru": "Занавеска"},
    "opt_rug":                {"tr": "Halı / Kilim",        "en": "Rug / Carpet",        "ar": "سجادة",                  "ru": "Ковёр"},

    # ── Lighting ──────────────────────────────────────────────────────────────
    "opt_chandelier":         {"tr": "Avize",               "en": "Chandelier",          "ar": "ثريا",                   "ru": "Люстра"},
    "opt_lampshade":          {"tr": "Abajur",              "en": "Lampshade",           "ar": "مصباح أباجور",           "ru": "Абажур"},
    "opt_desk_lamp":          {"tr": "Masa Lambası",        "en": "Desk Lamp",           "ar": "مصباح مكتبي",            "ru": "Настольная лампа"},
    "opt_wall_lamp":          {"tr": "Aplik",               "en": "Wall Lamp",           "ar": "مصباح جداري",            "ru": "Настенный светильник"},
    "opt_floor_lamp":         {"tr": "Ayak Lambası",        "en": "Floor Lamp",          "ar": "مصباح أرضي",             "ru": "Торшер"},

    # ── Bicycle types ─────────────────────────────────────────────────────────
    "opt_mountain":           {"tr": "Dağ Bisikleti",       "en": "Mountain Bike",       "ar": "دراجة جبلية",            "ru": "Горный велосипед"},
    "opt_road":               {"tr": "Yol Bisikleti",       "en": "Road Bike",           "ar": "دراجة طريق",             "ru": "Шоссейный велосипед"},
    "opt_city":               {"tr": "Şehir Bisikleti",     "en": "City Bike",           "ar": "دراجة مدينة",            "ru": "Городской велосипед"},
    "opt_bmx":                {"tr": "BMX",                 "en": "BMX",                 "ar": "دراجة BMX",              "ru": "BMX"},
    "opt_electric_bike":      {"tr": "Elektrikli Bisiklet", "en": "Electric Bike",       "ar": "دراجة كهربائية",         "ru": "Электровелосипед"},
    "opt_folding":            {"tr": "Katlanan Bisiklet",   "en": "Folding Bike",        "ar": "دراجة قابلة للطي",       "ru": "Складной велосипед"},

    # ── Sports ────────────────────────────────────────────────────────────────
    "opt_football":           {"tr": "Futbol",              "en": "Football",            "ar": "كرة القدم",              "ru": "Футбол"},
    "opt_basketball":         {"tr": "Basketbol",           "en": "Basketball",          "ar": "كرة السلة",              "ru": "Баскетбол"},
    "opt_volleyball":         {"tr": "Voleybol",            "en": "Volleyball",          "ar": "كرة الطائرة",            "ru": "Волейбол"},
    "opt_tennis":             {"tr": "Tenis",               "en": "Tennis",              "ar": "تنس",                    "ru": "Теннис"},
    "opt_swimming":           {"tr": "Yüzme",               "en": "Swimming",            "ar": "سباحة",                  "ru": "Плавание"},
    "opt_running":            {"tr": "Koşu",                "en": "Running",             "ar": "جري",                    "ru": "Бег"},
    "opt_boxing":             {"tr": "Boks / Muay Thai",    "en": "Boxing / Muay Thai",  "ar": "ملاكمة / موي تاي",       "ru": "Бокс / Муай-тай"},
    "opt_yoga":               {"tr": "Yoga / Pilates",      "en": "Yoga / Pilates",      "ar": "يوغا / بيلاتس",           "ru": "Йога / Пилатес"},
    "opt_outdoor":            {"tr": "Doğa Sporları",       "en": "Outdoor Sports",      "ar": "رياضات خارجية",          "ru": "Outdoor-спорт"},

    # ── Pets ──────────────────────────────────────────────────────────────────
    "opt_dog":                {"tr": "Köpek",               "en": "Dog",                 "ar": "كلب",                    "ru": "Собака"},
    "opt_cat":                {"tr": "Kedi",                "en": "Cat",                 "ar": "قطة",                   "ru": "Кошка"},
    "opt_bird":               {"tr": "Kuş",                 "en": "Bird",                "ar": "طائر",                   "ru": "Птица"},
    "opt_fish":               {"tr": "Balık",               "en": "Fish",                "ar": "سمكة",                   "ru": "Рыба"},
    "opt_hamster":            {"tr": "Hamster",             "en": "Hamster",             "ar": "هامستر",                 "ru": "Хомяк"},
    "opt_rabbit":             {"tr": "Tavşan",              "en": "Rabbit",              "ar": "أرنب",                   "ru": "Кролик"},

    # ── Music instruments ─────────────────────────────────────────────────────
    "opt_guitar":             {"tr": "Gitar",               "en": "Guitar",              "ar": "غيتار",                  "ru": "Гитара"},
    "opt_piano":              {"tr": "Piyano / Klavye",     "en": "Piano / Keyboard",    "ar": "بيانو / لوحة مفاتيح",    "ru": "Пианино / Клавиатура"},
    "opt_drums":              {"tr": "Davul / Perküsyon",   "en": "Drums / Percussion",  "ar": "طبول / إيقاع",           "ru": "Ударные"},
    "opt_violin":             {"tr": "Keman",               "en": "Violin",              "ar": "كمان",                   "ru": "Скрипка"},
    "opt_saz":                {"tr": "Saz / Bağlama",       "en": "Saz / Baglama",       "ar": "ساز / بغلاما",           "ru": "Саз / Баглама"},
    "opt_flute":              {"tr": "Flüt",                "en": "Flute",               "ar": "ناي / فلوت",              "ru": "Флейта"},
}


def _read_arb(lang: str) -> dict[str, str]:
    path = os.path.join(_ARB_DIR, f"app_{lang}.arb")
    with open(path, encoding="utf-8") as f:
        raw: dict = json.load(f)
    return {
        k: v
        for k, v in raw.items()
        if not k.startswith("@") and isinstance(v, str)
    }


async def sync() -> None:
    totals: dict[str, int] = {}

    async with AsyncSessionLocal() as session:
        for lang in _LANGS:
            pack = _read_arb(lang)
            if not pack:
                print(f"[sync_translations] WARN: {lang} ARB boş, atlandı")
                continue

            # Merge opt_* static translations into the pack
            for key, langs in _OPT_TRANSLATIONS.items():
                if lang in langs:
                    pack[key] = langs[lang]

            await session.execute(
                sa.text(
                    "INSERT INTO translations (key, lang, value) "
                    "SELECT unnest(:keys), :lang, unnest(:values) "
                    "ON CONFLICT (key, lang) DO UPDATE SET value = EXCLUDED.value"
                ).bindparams(
                    bindparam("keys", type_=ARRAY(Text)),
                    bindparam("values", type_=ARRAY(Text)),
                ),
                {
                    "keys": list(pack.keys()),
                    "lang": lang,
                    "values": list(pack.values()),
                },
            )
            totals[lang] = len(pack)

        await session.commit()

    # Redis cache'i invalidate et — bir sonraki /api/i18n/{lang} isteğinde taze veri gelir
    try:
        redis = await get_redis()
        for lang in _LANGS:
            await redis.delete(f"i18n:{lang}")
            await redis.delete(f"i18n:{lang}:version")
        # Catalog cache'ini de temizle (fastapi_cache keys)
        catalog_keys = await redis.keys("fastapi-cache*catalog*")
        if catalog_keys:
            await redis.delete(*catalog_keys)
            print(f"[sync_translations] Catalog cache temizlendi ({len(catalog_keys)} key)")
        print("[sync_translations] Redis i18n cache temizlendi")
    except Exception as exc:
        print(f"[sync_translations] WARN: Redis cache temizlenemedi: {exc}")

    for lang, count in totals.items():
        print(f"[sync_translations] {lang}: {count} key sync'lendi")

    total = sum(totals.values())
    print(f"[sync_translations] Toplam: {total} satır upsert edildi")


if __name__ == "__main__":
    asyncio.run(sync())
