#!/usr/bin/env python3
"""
insert_02_user_interactions.py — mock_02_user_interactions.json → PostgreSQL user_interactions

listing_ids.json'dan listing_idx → real_id eşlemesini okur.

Çalıştırma (backend dizininde, insert_01 sonrası):
  python documents/mock_data/insert_02_user_interactions.py

Çıktı:
  ✓ X event eklendi, Y atlandı (eşleşmeyen listing_idx)
"""
import asyncio
import json
from pathlib import Path

import asyncpg

DATA_FILE = Path(__file__).parent / "mock_02_user_interactions.json"
IDS_FILE  = Path(__file__).parent / "listing_ids.json"
DB_DSN    = "postgresql://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"
BATCH     = 500

INSERT_SQL = """
INSERT INTO user_interactions
    (user_id, item_id, item_type, interaction_type, duration_seconds, created_at)
VALUES ($1, $2, $3, $4, $5, $6::timestamptz)
"""


async def main() -> None:
    if not IDS_FILE.exists():
        print("HATA: listing_ids.json bulunamadı — önce insert_01_listings.py çalıştır")
        return

    idx_to_id: dict[str, int] = json.loads(IDS_FILE.read_text(encoding="utf-8"))
    data: list[dict] = json.loads(DATA_FILE.read_text(encoding="utf-8"))

    conn = await asyncpg.connect(DB_DSN)

    rows = []
    skipped = 0
    for ev in data:
        real_id = idx_to_id.get(str(ev["listing_idx"]))
        if real_id is None:
            skipped += 1
            continue
        rows.append((
            ev["user_id"],
            real_id,
            ev["item_type"],
            ev["interaction_type"],
            ev.get("duration_seconds"),
            ev["created_at"],
        ))

    inserted = 0
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        await conn.executemany(INSERT_SQL, batch)
        inserted += len(batch)

    await conn.close()
    print(f"✓ {inserted} event eklendi, {skipped} atlandı (eşleşmeyen listing_idx)")


asyncio.run(main())
