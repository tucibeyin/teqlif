"""
Kategori Talep Trendi ekranı için ClickHouse search_events tablosuna test verisi ekler.

/analytics/demand-trends endpoint'i her kategori için en az 2 haftalık veri gerektirir.
Bu script 8 haftalık gerçekçi arama verisi üretir.

VPS kullanımı:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate

  # Mevcut veriyi gör + seed et:
  python scripts/seed_search_events.py

  # Sadece mevcut veriyi kontrol et (insert etmeden):
  python scripts/seed_search_events.py --check

  # Seed verisini sil:
  python scripts/seed_search_events.py --clear
"""
import asyncio
import os
import sys
import random
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MODE = sys.argv[1] if len(sys.argv) > 1 else ""

CATEGORIES = [
    "elektronik",
    "giyim",
    "ev_esyalari",
    "kitap",
    "spor",
    "oyuncak",
    "muzik_aleti",
    "koleksiyonluk",
]

SAMPLE_QUERIES = {
    "elektronik":    ["telefon", "laptop", "kulaklık", "tablet", "klavye", "monitör"],
    "giyim":         ["elbise", "gömlek", "pantolon", "ceket", "sneaker", "çanta"],
    "ev_esyalari":   ["kanepe", "masa", "sandalye", "halı", "avize", "dekor"],
    "kitap":         ["roman", "tarih kitabı", "çocuk kitabı", "bilim kurgu", "polisiye"],
    "spor":          ["dumbbell", "koşu ayakkabısı", "yoga matı", "bisiklet", "tenis raketi"],
    "oyuncak":       ["lego", "bebek", "araba oyuncak", "puzzle", "tahta oyuncak"],
    "muzik_aleti":   ["gitar", "keman", "piyano", "davul", "flüt", "ukulele"],
    "koleksiyonluk": ["pul", "antika saat", "eski para", "figür", "vintage poster"],
}


async def check(ch):
    print("\n── Mevcut search_events durumu ──────────────────────────────")
    r = await ch.query("""
        SELECT category, toStartOfWeek(timestamp, 1) AS week, count() AS cnt
        FROM search_events
        WHERE category != ''
        GROUP BY category, week
        ORDER BY category, week
    """)
    if not r.result_rows:
        print("  (tablo boş)")
        return
    cur_cat = None
    for row in r.result_rows:
        cat, week, cnt = row
        if cat != cur_cat:
            cur_cat = cat
            print(f"\n  {cat}")
        print(f"    {week}  →  {cnt} arama")

    r2 = await ch.query("SELECT count() FROM search_events")
    total = r2.result_rows[0][0]
    print(f"\n  Toplam satır: {total}")


async def clear(ch):
    print("\n── Seed verisi siliniyor… ────────────────────────────────────")
    await ch.command("TRUNCATE TABLE search_events")
    print("  Tablo temizlendi (TRUNCATE).")


async def seed(ch):
    print("\n── Test verisi ekleniyor… ────────────────────────────────────")
    now = datetime.now(timezone.utc)

    rows = []
    for cat in CATEGORIES:
        queries = SAMPLE_QUERIES[cat]
        for week_offset in range(8):          # 8 hafta geriye git
            week_start = now - timedelta(weeks=week_offset + 1)
            # Her hafta 15-40 arama ekle, gerçekçi dalgalanma
            count = random.randint(15, 40)
            for _ in range(count):
                # Hafta içinde rastgele bir an
                ts = week_start + timedelta(
                    days=random.randint(0, 6),
                    hours=random.randint(0, 23),
                    minutes=random.randint(0, 59),
                )
                query_str = random.choice(queries)
                # Zaman zaman sonuç yok (zero_result_count için)
                result_count = 0 if random.random() < 0.12 else random.randint(1, 50)
                intent = random.choice(["buy", "browse", "compare", ""])
                user_id = random.randint(1, 20) if random.random() < 0.8 else None

                rows.append([
                    ts.replace(tzinfo=None),  # timestamp — naive datetime (UTC)
                    user_id,                  # user_id (nullable)
                    query_str,                # query
                    cat,                      # category
                    result_count,             # result_count
                    intent,                   # intent
                ])

    # clickhouse_connect'in insert() metodu: (tablo, veri, sütun_isimleri)
    await ch.insert(
        "search_events",
        rows,
        column_names=["timestamp", "user_id", "query", "category", "result_count", "intent"],
    )

    total = len(rows)
    print(f"  {total} satır eklendi ({len(CATEGORIES)} kategori × 8 hafta)")
    print(f"  Kategoriler: {', '.join(CATEGORIES)}")


async def main():
    from app.database_clickhouse import get_clickhouse_client

    ch = await get_clickhouse_client()

    if MODE == "--clear":
        await clear(ch)
    elif MODE == "--check":
        await check(ch)
    else:
        await check(ch)
        await seed(ch)
        print()
        await check(ch)

    await ch.close()
    print()


asyncio.run(main())
