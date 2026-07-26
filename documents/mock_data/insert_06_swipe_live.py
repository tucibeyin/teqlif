#!/usr/bin/env python3
"""
insert_06_swipe_live.py — mock_06_swipe_live.json → ClickHouse swipe_live_events

listing_ids.json'dan listing_idx → real_id eşlemesini okur.
listing_id kolonu UInt32 tipinde — int(real_id) olarak girilir.

Çalıştırma (backend dizininde, insert_01 sonrası):
  python documents/mock_data/insert_06_swipe_live.py

Çıktı:
  ✓ X swipe_live_events satırı eklendi
"""
import json
from datetime import datetime, timezone
from pathlib import Path

import clickhouse_connect

DATA_FILE = Path(__file__).parent / "mock_06_swipe_live.json"
IDS_FILE  = Path(__file__).parent / "listing_ids.json"
BATCH     = 1000

COLUMNS = [
    "user_id", "stream_id", "listing_id", "event_type", "dwell_ms",
    "stream_category", "stream_subcategory",
    "listing_category", "listing_subcategory", "listing_condition",
    "listings_seen", "slot_index", "session_id", "timestamp",
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
            ev["user_id"],
            ev["stream_id"],
            real_id,                             # UInt32
            ev["event_type"],
            ev["dwell_ms"],
            ev.get("stream_category", ""),
            ev.get("stream_subcategory", ""),
            ev.get("listing_category", ""),
            ev.get("listing_subcategory", ""),
            ev.get("listing_condition", ""),
            ev.get("listings_seen", 1),
            ev.get("slot_index", 0),
            ev.get("session_id", ""),
            parse_dt(ev["timestamp"]),
        ])

    inserted = 0
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        client.insert("swipe_live_events", batch, column_names=COLUMNS)
        inserted += len(batch)

    if skipped:
        print(f"  {skipped} satır atlandı (eşleşmeyen listing_idx)")
    print(f"✓ {inserted} swipe_live_events satırı eklendi")


main()
