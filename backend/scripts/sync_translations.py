"""
ARB dosyalarını translations tablosuna sync'ler.

Kullanım (VPS'te):
    cd /var/www/teqlif.com/backend
    source /var/www/teqlif.com/venv/bin/activate
    python scripts/sync_translations.py

Ne yapar:
  - mobile/lib/l10n/app_{tr,en,ar,ru}.arb dosyalarını okur
  - @-annotation ve @@locale satırlarını atlar
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
