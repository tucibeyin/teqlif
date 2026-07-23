"""
Piyasa Zekası ekranı verilerini doğrular (market-trends + demand-radar).
Platform geneli veridir — user'a özel değil.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/market_intelligence_check.py [days]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from sqlalchemy import text
    from app.database import AsyncSessionLocal
    from app.database_clickhouse import get_clickhouse_client

    ch = await get_clickhouse_client()

    # ── 1. Peak Hours (user_events, son 30 gün) ────────────────────────────
    sep("1. PEAK HOURS  (market-trends → user_events)")
    ph_rows = (await ch.query("""
        SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
        FROM user_events
        WHERE timestamp >= now() - INTERVAL 30 DAY
        GROUP BY hr
        ORDER BY cnt DESC
        LIMIT 5
    """)).result_rows

    total_events = (await ch.query("""
        SELECT COUNT(*) FROM user_events
        WHERE timestamp >= now() - INTERVAL 30 DAY
    """)).result_rows[0][0]

    print(f"  Son 30 günde user_events toplam: {int(total_events)}")
    print(f"\n  {'Saat':<8}  {'Olay sayısı':>12}  Bar")
    print(f"  {'─'*40}")
    max_cnt = max((int(r[1]) for r in ph_rows), default=1)
    for row in ph_rows:
        hr, cnt = int(row[0]), int(row[1])
        bar = '█' * int(cnt / max_cnt * 20)
        print(f"  {hr:02d}:00    {cnt:>12}  {bar}")
    if not ph_rows:
        print("  (user_events kaydı yok)")

    # ── 2. Trending Categories (purchases + auctions + listings) ──────────
    sep("2. TRENDING CATEGORIES  (market-trends → PostgreSQL)")
    async with AsyncSessionLocal() as db:
        cat_r = (await db.execute(text("""
            WITH recent AS (
                SELECT l.category, COUNT(*) AS cnt
                FROM purchases p
                JOIN auctions a ON a.id = p.auction_id
                JOIN listings  l ON l.id = a.listing_id
                WHERE p.created_at >= NOW() - INTERVAL '15 days'
                  AND p.auction_id IS NOT NULL AND l.category IS NOT NULL
                GROUP BY l.category
            ),
            prev AS (
                SELECT l.category, COUNT(*) AS cnt
                FROM purchases p
                JOIN auctions a ON a.id = p.auction_id
                JOIN listings  l ON l.id = a.listing_id
                WHERE p.created_at >= NOW() - INTERVAL '30 days'
                  AND p.created_at  < NOW() - INTERVAL '15 days'
                  AND p.auction_id IS NOT NULL AND l.category IS NOT NULL
                GROUP BY l.category
            )
            SELECT
                r.category,
                r.cnt AS recent_cnt,
                COALESCE(p.cnt, 0) AS prev_cnt,
                CASE WHEN COALESCE(p.cnt, 0) > 0 AND r.cnt >= 3
                    THEN ROUND(((r.cnt - p.cnt)::float / p.cnt * 100)::numeric, 1)
                    ELSE NULL
                END AS growth_pct
            FROM recent r
            LEFT JOIN prev p ON p.category = r.category
            WHERE r.cnt >= 3
            ORDER BY COALESCE(
                CASE WHEN COALESCE(p.cnt, 0) > 0 AND r.cnt >= 3
                    THEN (r.cnt - p.cnt)::float / p.cnt * 100
                    ELSE NULL
                END, 0) DESC
            LIMIT 5
        """))).fetchall()

        if cat_r:
            print(f"  {'Kategori':<15}  {'Son15g':>8}  {'Önceki15g':>10}  {'Büyüme%':>9}")
            print(f"  {'─'*50}")
            for r in cat_r:
                g = f"%{float(r.growth_pct):+.1f}" if r.growth_pct is not None else "yeni"
                print(f"  {(r.category or 'other'):<15}  {int(r.recent_cnt):>8}  {int(r.prev_cnt):>10}  {g:>9}")
        else:
            print("  ⚠ Trending kategori için yeterli veri yok (min 3 satış/15 gün)")

        # ── 3. Average Spend Growth ────────────────────────────────────────
        sep("3. AVERAGE SPEND GROWTH  (market-trends → purchases)")
        sp_r = (await db.execute(text("""
            SELECT
                AVG(price) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')      AS recent_avg,
                COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')         AS recent_cnt,
                AVG(price) FILTER (WHERE created_at >= NOW() - INTERVAL '60 days'
                                    AND created_at <  NOW() - INTERVAL '30 days')        AS prev_avg,
                COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '60 days'
                                    AND created_at <  NOW() - INTERVAL '30 days')        AS prev_cnt
            FROM purchases
        """))).fetchone()

        r_avg  = float(sp_r.recent_avg or 0)
        p_avg  = float(sp_r.prev_avg or 0)
        r_cnt  = int(sp_r.recent_cnt or 0)
        p_cnt  = int(sp_r.prev_cnt or 0)
        growth = round((r_avg - p_avg) / p_avg * 100, 1) if p_avg > 0 else None

        print(f"  Son 30 gün: {r_cnt} satış, ort. {r_avg:.0f}₺")
        print(f"  Önceki 30 gün: {p_cnt} satış, ort. {p_avg:.0f}₺")
        print(f"  Büyüme: {f'%{growth:+.1f}' if growth is not None else '—'}")
        if r_avg == 0:
            print("  ⚠ Son 30 günde satış yok → ekranda growth banner gösterilmez")

    # ── 4. Demand Radar — search_events tablosu ────────────────────────────
    sep(f"4. DEMAND RADAR  (demand-radar, son {DAYS} gün → search_events)")
    try:
        # Tablo var mı?
        tbl_check = (await ch.query("""
            SELECT COUNT(*) FROM search_events
            WHERE timestamp >= now() - INTERVAL 30 DAY
        """)).result_rows
        total_searches = int(tbl_check[0][0]) if tbl_check else 0
        print(f"  Son 30 günde search_events toplam: {total_searches}")

        top_q = (await ch.query(f"""
            SELECT query, COUNT(*) AS cnt
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {DAYS} DAY
              AND length(query) >= 2
            GROUP BY query
            HAVING cnt >= 2
            ORDER BY cnt DESC
            LIMIT 10
        """)).result_rows

        print(f"\n  Top aramalar (son {DAYS} gün, min 2 tekrar):")
        if top_q:
            for i, (q, cnt) in enumerate(top_q):
                print(f"  {i+1:>2}. {q:<25} {int(cnt):>5}x")
        else:
            print("  (yeterli arama verisi yok — cnt>=2 filtresi)")

        by_cat = (await ch.query(f"""
            SELECT category, COUNT(*) AS cnt
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {DAYS} DAY
              AND category != ''
            GROUP BY category
            HAVING cnt >= 2
            ORDER BY cnt DESC
            LIMIT 10
        """)).result_rows

        print(f"\n  Kategori bazlı aramalar (son {DAYS} gün):")
        if by_cat:
            for cat, cnt in by_cat:
                print(f"  {cat:<20} {int(cnt):>6}x")
        else:
            print("  (kategori araması yok ya da < 2 tekrar)")

    except Exception as e:
        print(f"  ⚠ search_events hatası: {e}")
        print("  → search_events tablosu ClickHouse'da olmayabilir")

    print()


asyncio.run(main())
