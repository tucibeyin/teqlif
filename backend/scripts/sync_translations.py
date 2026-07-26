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
# Format: key -> {lang: value}
_OPT_TRANSLATIONS: dict[str, dict[str, str]] = {
    "opt_white":              {"tr": "Beyaz",             "en": "White",            "ar": "أبيض",                      "ru": "Белый"},
    "opt_gray":               {"tr": "Gri",               "en": "Gray",             "ar": "رمادي",                     "ru": "Серый"},
    "opt_black":              {"tr": "Siyah",             "en": "Black",            "ar": "أسود",                      "ru": "Чёрный"},
    "opt_blue":               {"tr": "Mavi",              "en": "Blue",             "ar": "أزرق",                      "ru": "Синий"},
    "opt_red":                {"tr": "Kırmızı",           "en": "Red",              "ar": "أحمر",                      "ru": "Красный"},
    "opt_green":              {"tr": "Yeşil",             "en": "Green",            "ar": "أخضر",                      "ru": "Зелёный"},
    "opt_yellow":             {"tr": "Sarı",              "en": "Yellow",           "ar": "أصفر",                      "ru": "Жёлтый"},
    "opt_orange":             {"tr": "Turuncu",           "en": "Orange",           "ar": "برتقالي",                   "ru": "Оранжевый"},
    "opt_purple":             {"tr": "Mor",               "en": "Purple",           "ar": "بنفسجي",                    "ru": "Фиолетовый"},
    "opt_pink":               {"tr": "Pembe",             "en": "Pink",             "ar": "وردي",                      "ru": "Розовый"},
    "opt_brown":              {"tr": "Kahverengi",        "en": "Brown",            "ar": "بني",                       "ru": "Коричневый"},
    "opt_beige":              {"tr": "Bej",               "en": "Beige",            "ar": "بيج",                       "ru": "Бежевый"},
    "opt_gold":               {"tr": "Altın",             "en": "Gold",             "ar": "ذهبي",                      "ru": "Золотой"},
    "opt_silver":             {"tr": "Gümüş",             "en": "Silver",           "ar": "فضي",                       "ru": "Серебристый"},
    "opt_gasoline":           {"tr": "Benzin",            "en": "Gasoline",         "ar": "بنزين",                     "ru": "Бензин"},
    "opt_diesel":             {"tr": "Dizel",             "en": "Diesel",           "ar": "ديزل",                      "ru": "Дизель"},
    "opt_lpg":                {"tr": "LPG",               "en": "LPG",              "ar": "غاز البترول المسال",        "ru": "СНГ"},
    "opt_hybrid":             {"tr": "Hibrit",            "en": "Hybrid",           "ar": "هجين",                      "ru": "Гибрид"},
    "opt_electric":           {"tr": "Elektrik",          "en": "Electric",         "ar": "كهربائي",                   "ru": "Электрический"},
    "opt_manual":             {"tr": "Manuel",            "en": "Manual",           "ar": "يدوي",                      "ru": "Ручная"},
    "opt_automatic":          {"tr": "Otomatik",          "en": "Automatic",        "ar": "أوتوماتيك",                 "ru": "Автомат"},
    "opt_semi_automatic":     {"tr": "Yarı Otomatik",    "en": "Semi-Automatic",   "ar": "نصف أوتوماتيك",             "ru": "Полуавтомат"},
    "opt_sedan":              {"tr": "Sedan",             "en": "Sedan",            "ar": "سيدان",                     "ru": "Седан"},
    "opt_hatchback":          {"tr": "Hatchback",         "en": "Hatchback",        "ar": "هاتشباك",                   "ru": "Хэтчбек"},
    "opt_suv":                {"tr": "SUV",               "en": "SUV",              "ar": "سيارة رباعية الدفع",        "ru": "Внедорожник"},
    "opt_station_wagon":      {"tr": "Station Wagon",    "en": "Station Wagon",    "ar": "ستيشن واجن",                "ru": "Универсал"},
    "opt_coupe":              {"tr": "Coupe",             "en": "Coupe",            "ar": "كوبيه",                     "ru": "Купه"},
    "opt_cabriolet":          {"tr": "Cabriolet",        "en": "Cabriolet",        "ar": "كابريوليه",                  "ru": "Кабриолет"},
    "opt_pickup":             {"tr": "Pickup",            "en": "Pickup",           "ar": "بيكاب",                     "ru": "Пикап"},
    "opt_van":                {"tr": "Van",               "en": "Van",              "ar": "فان",                       "ru": "Фургон"},
    "opt_minibus":            {"tr": "Minibüs",           "en": "Minibus",          "ar": "ميني باص",                  "ru": "Микроавтобус"},
    "opt_painted":            {"tr": "Boyalı",            "en": "Painted",          "ar": "مطلي",                      "ru": "Крашеный"},
    "opt_damage_record":      {"tr": "Hasar Kayıtlı",    "en": "Damage Record",    "ar": "سجل الأضرار",               "ru": "Повреждения в записях"},
    "opt_heavy_damage_record":{"tr": "Ağır Hasar Kayıtlı","en": "Heavy Damage Record","ar": "سجل الأضرار الجسيمة",   "ru": "Серьёзные повреждения"},
    "opt_flawless":           {"tr": "Hatasız",           "en": "Flawless",         "ar": "خالٍ من العيوب",            "ru": "Без дефектов"},
    "opt_other":              {"tr": "Diğer",             "en": "Other",            "ar": "أخرى",                      "ru": "Другое"},
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
        print("[sync_translations] Redis i18n cache temizlendi")
    except Exception as exc:
        print(f"[sync_translations] WARN: Redis cache temizlenemedi: {exc}")

    for lang, count in totals.items():
        print(f"[sync_translations] {lang}: {count} key sync'lendi")

    total = sum(totals.values())
    print(f"[sync_translations] Toplam: {total} satır upsert edildi")


if __name__ == "__main__":
    asyncio.run(sync())
