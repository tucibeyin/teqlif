#!/usr/bin/env python3
"""
insert_05_search_events.py — mock_05_search_events.json → ClickHouse search_events

Çalıştırma (backend dizininde):
  python documents/mock_data/insert_05_search_events.py

Çıktı:
  ✓ X search_events satırı eklendi
"""
import json
from datetime import datetime, timezone
from pathlib import Path

import clickhouse_connect

DATA_FILE = Path(__file__).parent / "mock_05_search_events.json"
BATCH     = 1000

COLUMNS = ["timestamp", "user_id", "query", "category", "subcategory", "result_count", "intent"]


def parse_dt(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)


def main() -> None:
    data: list[dict] = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    client = clickhouse_connect.get_client(host="localhost", port=8123)

    rows = [
        [
            parse_dt(ev["timestamp"]),
            ev.get("user_id"),          # Nullable(UInt32)
            ev["query"],
            ev.get("category", ""),
            ev.get("subcategory", ""),
            ev.get("result_count", 0),
            ev.get("intent", "browse"),
        ]
        for ev in data
    ]

    inserted = 0
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        client.insert("search_events", batch, column_names=COLUMNS)
        inserted += len(batch)

    print(f"✓ {inserted} search_events satırı eklendi")


main()
