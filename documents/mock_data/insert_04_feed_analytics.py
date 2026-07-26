#!/usr/bin/env python3
"""
insert_04_feed_analytics.py — mock_04_feed_analytics.json → ClickHouse feed_analytics

listing_ids.json'dan listing_idx → real_id eşlemesini okur.
listing_id kolonu String tipinde — str(real_id) olarak girilir.

Çalıştırma (backend dizininde, insert_01 sonrası):
  python documents/mock_data/insert_04_feed_analytics.py

Çıktı:
  ✓ X feed_analytics satırı eklendi
"""
import json
from datetime import datetime, timezone
from pathlib import Path

import clickhouse_connect

DATA_FILE = Path(__file__).parent / "mock_04_feed_analytics.json"
IDS_FILE  = Path(__file__).parent / "listing_ids.json"
BATCH     = 1000

COLUMNS = [
    "timestamp", "user_id", "listing_id", "event_type",
    "dwell_time_ms", "content_type", "slot_index",
    "stream_category", "listing_condition", "listing_subcategory",
]


def parse_dt(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)


def main() -> None:
    if not IDS_FILE.exists():
        print("HATA: listing_ids.json bulunamadı — önce insert_01_listings.py çalıştır")
        return

    idx_to_id: dict[str, int] = json.loads(IDS_FILE.read_text(encoding="utf-8"))
    data: list[dict] = json.loads(DATA_FILE.read_text(encoding="utf-8"))

    client = clickhouse_connect.get_client(host="localhost", port=8123)

    rows = []
    skipped = 0
    for ev in data:
        real_id = idx_to_id.get(str(ev["listing_idx"]))
        if real_id is None:
            skipped += 1
            continue
        rows.append([
            parse_dt(ev["timestamp"]),
            ev["user_id"],               # String
            str(real_id),                # listing_id is String in ClickHouse
            ev["event_type"],
            ev["dwell_time_ms"],
            ev.get("content_type", "listing"),
            ev.get("slot_index", 0),
            ev.get("stream_category", ""),
            ev.get("listing_condition", ""),
            ev.get("listing_subcategory", ""),
        ])

    inserted = 0
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        client.insert("feed_analytics", batch, column_names=COLUMNS)
        inserted += len(batch)

    if skipped:
        print(f"  {skipped} satır atlandı (eşleşmeyen listing_idx)")
    print(f"✓ {inserted} feed_analytics satırı eklendi")


main()
