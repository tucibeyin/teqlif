"""
Satış ve Kitle Raporu verilerini VPS'den doğrular.
Her bölümü sırayla gösterir ve tutarsızlıkları işaretler.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/pro_insights_check.py [user_id]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UID = int(sys.argv[1]) if len(sys.argv) > 1 else 3


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from datetime import datetime, timedelta, timezone
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    now = datetime.now(timezone.utc)
    d30 = now - timedelta(days=30)
    d60 = now - timedelta(days=60)

    async with AsyncSessionLocal() as db:

        # ── 1. KPI'lar ────────────────────────────────────────────────────
        sep("1. KPI'LAR")
        lrow = (await db.execute(text("""
            SELECT
                COUNT(*)                                                        AS total_listings,
                COUNT(*) FILTER (WHERE is_active AND NOT is_deleted)            AS active_listings,
                COALESCE(AVG(price) FILTER (WHERE NOT is_deleted), 0)           AS avg_price,
                COUNT(*) FILTER (WHERE created_at >= :d30 AND NOT is_deleted)   AS new_30d
            FROM listings WHERE user_id = :uid
        """), {"uid": UID, "d30": d30})).fetchone()

        srow = (await db.execute(text("""
            SELECT
                COUNT(*)                                                            AS total_sales,
                COALESCE(SUM(price), 0)                                             AS total_revenue,
                COALESCE(SUM(price) FILTER (WHERE created_at >= :d30), 0)           AS rev_30d,
                COALESCE(SUM(price) FILTER (WHERE created_at >= :d60
                                             AND created_at < :d30), 0)             AS rev_prev_30d,
                COUNT(*) FILTER (WHERE created_at >= :d30)                          AS sales_30d
            FROM purchases
            WHERE buyer_id != :uid
              AND listing_id IN (SELECT id FROM listings WHERE user_id = :uid)
        """), {"uid": UID, "d30": d30, "d60": d60})).fetchone()

        brow = (await db.execute(text("""
            SELECT COUNT(*) AS total_bids
            FROM bids b
            JOIN auctions a ON a.stream_id = b.stream_id
            JOIN listings l ON l.id = a.listing_id
            WHERE l.user_id = :uid AND b.created_at >= :d30
        """), {"uid": UID, "d30": d30})).fetchone()

        rev_30  = float(srow.rev_30d or 0)
        rev_prev = float(srow.rev_prev_30d or 0)
        rev_growth = round(((rev_30 - rev_prev) / rev_prev) * 100, 1) if rev_prev > 0 else None

        print(f"  Toplam ilan         : {lrow.total_listings}")
        print(f"  Aktif ilan          : {lrow.active_listings}")
        print(f"  Ort. ilan fiyatı    : {float(lrow.avg_price):.0f}₺")
        print(f"  Son 30 gün yeni ilan: {lrow.new_30d}")
        print(f"  Toplam satış        : {srow.total_sales}")
        print(f"  Toplam ciro         : {float(srow.total_revenue):.0f}₺")
        print(f"  Son 30 gün ciro     : {rev_30:.0f}₺")
        print(f"  Önceki 30 gün ciro  : {rev_prev:.0f}₺")
        print(f"  Ciro büyümesi       : {rev_growth}%")
        print(f"  Son 30 gün satış    : {srow.sales_30d}")
        print(f"  Son 30 gün teklif   : {brow.total_bids}")

        # ── 2. Dönüşüm Hunisi ─────────────────────────────────────────────
        sep("2. DÖNÜŞÜM HUNİSİ")
        listing_ids = [r[0] for r in (await db.execute(
            select(Listing.id).where(Listing.user_id == UID, Listing.is_deleted == False)  # noqa
        )).fetchall()]

        views_total = hesitations = 0
        if listing_ids:
            ids_str = ", ".join(str(i) for i in listing_ids)
            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                ch_r = await ch.query(f"""
                    SELECT countIf(event_type='view') AS views,
                           countIf(event_type='dwell') AS dwells,
                           countIf(event_type='bid_hesitation') AS hesitations
                    FROM user_events
                    WHERE item_type='listing' AND item_id IN ({ids_str})
                      AND timestamp >= now() - INTERVAL 30 DAY
                """)
                r = ch_r.result_rows[0] if ch_r.result_rows else (0, 0, 0)
                views_total  = int(r[0] or 0)
                hesitations  = int(r[2] or 0)
            except Exception as e:
                print(f"  ⚠ ClickHouse hatası: {e}")

        bids  = int(brow.total_bids or 0)
        sales = int(srow.sales_30d or 0)
        print(f"  Görüntüleme (30g)   : {views_total}")
        print(f"  Tereddüt            : {hesitations}")
        print(f"  Teklif (30g)        : {bids}")
        print(f"  Satış (30g)         : {sales}")
        print(f"  Görüntüleme→Teklif  : %{round((bids/views_total)*100,1) if views_total else 0}")
        print(f"  Teklif→Satış        : %{round((sales/bids)*100,1) if bids else 0}")

        # ── 3. Sıcak Talepler ─────────────────────────────────────────────
        sep("3. SICAK TALEPLER (hot_leads)")
        active = (await db.execute(
            select(Listing.id, Listing.title, Listing.price, Listing.category)
            .where(Listing.user_id == UID, Listing.is_active == True, Listing.is_deleted == False)  # noqa
            .limit(20)
        )).fetchall()

        view_map = {r.id: 0 for r in active}
        hes_map  = {r.id: 0 for r in active}
        if active:
            ids_str2 = ", ".join(str(r.id) for r in active)
            try:
                ch = await get_clickhouse_client()
                ch_r2 = await ch.query(f"""
                    SELECT item_id,
                           countIf(event_type='view') AS views,
                           countIf(event_type='bid_hesitation') AS hes
                    FROM user_events
                    WHERE item_type='listing' AND item_id IN ({ids_str2})
                      AND timestamp >= now() - INTERVAL 30 DAY
                    GROUP BY item_id ORDER BY views DESC LIMIT 10
                """)
                view_map = {int(r[0]): int(r[1]) for r in ch_r2.result_rows}
                hes_map  = {int(r[0]): int(r[2]) for r in ch_r2.result_rows}
            except Exception as e:
                print(f"  ⚠ ClickHouse hatası: {e}")

        scored = sorted(active, key=lambda r: view_map.get(r.id,0) + hes_map.get(r.id,0)*3, reverse=True)
        print(f"  {'ID':>4}  {'view':>5}  {'hes':>4}  {'score':>6}  {'fiyat':>8}  Başlık")
        print(f"  {'─'*55}")
        for r in scored:
            v = view_map.get(r.id, 0)
            h = hes_map.get(r.id, 0)
            score = v + h * 3
            print(f"  {r.id:>4}  {v:>5}  {h:>4}  {score:>6}  {int(r.price or 0):>8}₺  {r.title[:28]}")

        # ── 4. Fiyat Zekası ────────────────────────────────────────────────
        sep("4. FİYAT ZEKASI (price_intel)")
        my_listings = (await db.execute(
            select(Listing.id, Listing.title, Listing.price, Listing.category, Listing.embedding)
            .where(Listing.user_id == UID, Listing.is_active == True, Listing.is_deleted == False,  # noqa
                   Listing.price.is_not(None))
            .limit(5)
        )).fetchall()

        for ml in my_listings:
            market_avg = None
            price_lo = float(ml.price) * 0.05
            price_hi = float(ml.price) * 20.0
            if ml.embedding is not None:
                try:
                    emb_str = "[" + ",".join(f"{x:.6f}" for x in ml.embedding) + "]"
                    sim_r = await db.execute(text("""
                        SELECT AVG(price) FROM (
                            SELECT price FROM listings
                            WHERE user_id != :uid AND category = :cat
                              AND is_active AND NOT is_deleted
                              AND price > :lo AND price < :hi AND embedding IS NOT NULL
                            ORDER BY embedding <=> CAST(:emb AS vector) LIMIT 10
                        ) sub
                    """), {"uid": UID, "emb": emb_str, "cat": ml.category,
                           "lo": price_lo, "hi": price_hi})
                    market_avg = sim_r.scalar()
                except Exception:
                    await db.rollback()

            if market_avg is None:
                cat_r = await db.execute(text("""
                    SELECT AVG(price) FROM listings
                    WHERE category=:cat AND user_id!=:uid
                      AND is_active AND NOT is_deleted
                      AND price > :lo AND price < :hi
                """), {"cat": ml.category, "uid": UID, "lo": price_lo, "hi": price_hi})
                market_avg = cat_r.scalar()

            if market_avg and market_avg > 0:
                diff = round(((ml.price - market_avg) / market_avg) * 100, 1)
                signal = "pahalı" if diff > 15 else ("ucuz" if diff < -15 else "uygun")
                print(f"  #{ml.id} {ml.title[:28]:<30} fiyat={int(ml.price)}₺  market_avg={int(market_avg)}₺  %{diff:+.1f} → {signal}")
            else:
                print(f"  #{ml.id} {ml.title[:28]:<30} fiyat={int(ml.price)}₺  → veri yok")

        # ── 5. Yayın Performansı ────────────────────────────────────────────
        sep("5. YAYIN PERFORMANSI (stream_stats)")
        st_r = (await db.execute(text("""
            SELECT COUNT(*) AS total, COALESCE(AVG(viewer_count),0) AS avg_v,
                   COALESCE(MAX(viewer_count),0) AS peak_v,
                   COALESCE(AVG(EXTRACT(EPOCH FROM (ended_at - started_at))/60),0) AS avg_dur
            FROM live_streams WHERE host_id=:uid AND is_live=false AND ended_at IS NOT NULL
        """), {"uid": UID})).fetchone()
        print(f"  Toplam yayın        : {st_r.total}")
        print(f"  Ort. izleyici       : {float(st_r.avg_v):.1f}")
        print(f"  Maks izleyici       : {float(st_r.peak_v):.0f}")
        print(f"  Ort. süre (dk)      : {float(st_r.avg_dur):.1f}")

        # ── 6. Peak Hours ───────────────────────────────────────────────────
        sep("6. EN İYİ YAYIN SAATİ (peak_hours)")
        ph_r = (await db.execute(text("""
            SELECT EXTRACT(HOUR FROM started_at AT TIME ZONE 'Europe/Istanbul') AS hr,
                   COUNT(*) AS cnt, COALESCE(AVG(viewer_count),0) AS avg_v
            FROM live_streams WHERE host_id=:uid AND is_live=false AND ended_at IS NOT NULL
            GROUP BY hr ORDER BY avg_v DESC LIMIT 5
        """), {"uid": UID})).fetchall()
        if ph_r:
            for r in ph_r:
                print(f"  Saat {int(r.hr):02d}:00  →  {int(r.cnt)} yayın, ort. {float(r.avg_v):.1f} izleyici")
        else:
            print("  (yayın yok)")

    print()


asyncio.run(main())
