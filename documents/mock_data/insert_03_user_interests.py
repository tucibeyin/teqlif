#!/usr/bin/env python3
"""
insert_03_user_interests.py — mock_03_user_interests.json → PostgreSQL user_interests

ON CONFLICT (user_id, category) → score ve subcategory güncellenir.

Çalıştırma (backend dizininde):
  python documents/mock_data/insert_03_user_interests.py

Çıktı:
  ✓ X satır upsert edildi
"""
import asyncio
import json
from pathlib import Path

import asyncpg

DATA_FILE = Path(__file__).parent / "mock_03_user_interests.json"
DB_DSN    = "postgresql://teqlif:xxx@127.0.0.1:5432/teqlif"
BATCH     = 500

UPSERT_SQL = """
INSERT INTO user_interests (user_id, category, subcategory, score)
VALUES ($1, $2, $3, $4)
ON CONFLICT ON CONSTRAINT uq_user_interest
DO UPDATE SET
    score      = EXCLUDED.score,
    subcategory = EXCLUDED.subcategory,
    updated_at = NOW()
"""


async def main() -> None:
    data: list[dict] = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    conn = await asyncpg.connect(DB_DSN)

    rows = [
        (r["user_id"], r["category"], r.get("subcategory"), r["score"])
        for r in data
    ]

    upserted = 0
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        await conn.executemany(UPSERT_SQL, batch)
        upserted += len(batch)

    await conn.close()
    print(f"✓ {upserted} satır upsert edildi")


asyncio.run(main())
