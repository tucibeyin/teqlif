#!/usr/bin/env python3
"""
insert_01_listings.py — mock_01_listings.json → PostgreSQL listings tablosu

Çalıştırma (backend dizininde):
  python documents/mock_data/insert_01_listings.py

Çıktı:
  ✓ X ilan eklendi, Y atlandı
  listing_ids.json kaydedildi (insert scriptleri bu dosyayı kullanır)
"""
import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

import asyncpg


def parse_dt(s: str | None) -> datetime | None:
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)

DATA_FILE = Path(__file__).parent / "mock_01_listings.json"
IDS_FILE  = Path(__file__).parent / "listing_ids.json"
DB_DSN    = "postgresql://teqlif:xxx@127.0.0.1:5432/teqlif"

INSERT_SQL = """
INSERT INTO listings
    (user_id, title, description, price, category, subcategory,
     brand, model_name, condition, province, district, location,
     image_url, image_urls, status, extra_fields, quality_score, created_at)
VALUES
    ($1, $2, $3, $4, $5, $6,
     $7, $8, $9, $10, $11, $12,
     $13, $14, $15::listingstatus, $16::jsonb, $17, $18::timestamptz)
RETURNING id
"""


async def main() -> None:
    data: list[dict] = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    conn = await asyncpg.connect(DB_DSN)

    existing = await conn.fetch("SELECT user_id, title FROM listings")
    existing_set: set[tuple] = {(r["user_id"], r["title"]) for r in existing}

    idx_to_id: dict[str, int] = {}
    inserted = 0
    skipped  = 0

    for item in data:
        key = (item["user_id"], item["title"])
        if key in existing_set:
            skipped += 1
            continue

        ef = item.get("extra_fields")
        row = await conn.fetchrow(
            INSERT_SQL,
            item["user_id"],
            item["title"],
            item.get("description"),
            item.get("price"),
            item.get("category"),
            item.get("subcategory"),
            item.get("brand"),
            item.get("model_name"),
            item.get("condition"),
            item.get("province"),
            item.get("district"),
            item.get("location"),
            item.get("image_url"),
            item.get("image_urls"),
            item.get("status", "active"),
            json.dumps(ef, ensure_ascii=False) if ef else None,
            item.get("quality_score"),
            parse_dt(item.get("created_at")),
        )
        idx_to_id[str(item["listing_idx"])] = row["id"]
        existing_set.add(key)
        inserted += 1

    await conn.close()

    IDS_FILE.write_text(json.dumps(idx_to_id), encoding="utf-8")
    print(f"✓ {inserted} ilan eklendi, {skipped} atlandı")
    print(f"listing_ids.json kaydedildi ({len(idx_to_id)} kayıt)")


asyncio.run(main())
