"""
En İyi Yayın Saati + Dönüşüm Analizi verilerini doğrular.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/stream_conversion_check.py [user_id]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UID = int(sys.argv[1]) if len(sys.argv) > 1 else 3


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from sqlalchemy import text
    from app.database import AsyncSessionLocal

    _DAYS = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]

    async with AsyncSessionLocal() as db:

        # ── 0. Temel veri özeti ───────────────────────────────────────────
        sep("0. VERİ ÖZETİ")
        stats = (await db.execute(text("""
            SELECT
                (SELECT COUNT(*) FROM live_streams
                 WHERE host_id=:uid AND ended_at IS NOT NULL) AS total_streams,
                (SELECT COUNT(*) FROM live_streams
                 WHERE host_id=:uid AND ended_at IS NOT NULL
                   AND started_at >= NOW() - INTERVAL '90 days') AS streams_90d,
                (SELECT COUNT(*) FROM auctions a
                 JOIN live_streams ls ON ls.id = a.stream_id
                 WHERE ls.host_id=:uid) AS total_auctions,
                (SELECT COUNT(*) FROM auctions a
                 JOIN live_streams ls ON ls.id = a.stream_id
                 WHERE ls.host_id=:uid AND a.winner_id IS NOT NULL) AS won_auctions
        """), {"uid": UID})).fetchone()

        print(f"  Toplam yayın        : {stats.total_streams}")
        print(f"  Son 90 gün yayın    : {stats.streams_90d}")
        print(f"  Toplam açık artırma : {stats.total_auctions}")
        print(f"  Kazanılan           : {stats.won_auctions}")
        if int(stats.streams_90d) < 2:
            print("  ⚠ 90 günde < 2 yayın → best-stream-time boş döner (min. 2 yayın/blok)")

        # ── 1. En İyi Yayın Saati ─────────────────────────────────────────
        sep("1. EN İYİ YAYIN SAATİ  (best-stream-time, son 90 gün)")
        bst = (await db.execute(text("""
            WITH stream_auctions AS (
                SELECT
                    ls.id AS stream_id,
                    EXTRACT(DOW FROM ls.started_at AT TIME ZONE 'Europe/Istanbul')::int AS day_of_week,
                    FLOOR(EXTRACT(HOUR FROM ls.started_at AT TIME ZONE 'Europe/Istanbul') / 3) * 3 AS hour_block,
                    COUNT(a.id) AS total_auctions,
                    COUNT(a.winner_id) AS won_auctions
                FROM live_streams ls
                LEFT JOIN auctions a ON a.stream_id = ls.id
                WHERE ls.host_id = :uid
                  AND ls.started_at >= NOW() - INTERVAL '90 days'
                  AND ls.ended_at IS NOT NULL
                GROUP BY ls.id, ls.started_at
            )
            SELECT
                day_of_week,
                hour_block::int,
                COUNT(*) AS stream_count,
                COALESCE(SUM(won_auctions)::float / NULLIF(SUM(total_auctions), 0), 0) AS conv_rate,
                SUM(won_auctions) AS total_wins,
                SUM(total_auctions) AS total_auctions
            FROM stream_auctions
            GROUP BY day_of_week, hour_block
            ORDER BY conv_rate DESC, total_wins DESC
        """), {"uid": UID})).fetchall()

        if bst:
            print(f"  {'Gün':<12}  {'Saat':<15}  {'Yayın':>6}  {'Kazanılan':>10}  {'Toplam':>7}  {'Dönüşüm%':>10}  {'Ekranda?':>8}")
            print(f"  {'─'*70}")
            for r in bst:
                day_name = _DAYS[int(r.day_of_week)]
                hr = int(r.hour_block)
                conv = round(float(r.conv_rate) * 100, 1)
                shown = "✓" if int(r.stream_count) >= 2 else "✗ (< 2)"
                print(f"  {day_name:<12}  {hr:02d}:00-{hr+3:02d}:00    {int(r.stream_count):>6}  {int(r.total_wins):>10}  {int(r.total_auctions):>7}  {conv:>10.1f}%  {shown:>8}")
        else:
            print("  (Son 90 günde hiç yayın yok)")

        # Ekranda gösterilecek slot sayısı (HAVING COUNT(*) >= 2)
        shown_count = sum(1 for r in bst if int(r.stream_count) >= 2)
        print(f"\n  Ekranda gösterilecek slot (min 2 yayın/blok): {shown_count}")

        # ── 2. Dönüşüm Analizi ────────────────────────────────────────────
        sep("2. DÖNÜŞÜM ANALİZİ  (conversion-breakdown, son 90 gün)")
        cb = (await db.execute(text("""
            SELECT
                COALESCE(l.category, 'diger') AS category,
                COUNT(a.id) AS total_auctions,
                COUNT(a.winner_id) AS won_auctions,
                COALESCE(AVG(a.final_price) FILTER (WHERE a.winner_id IS NOT NULL), 0) AS avg_final_price,
                COALESCE(COUNT(a.winner_id)::float / NULLIF(COUNT(a.id), 0), 0) AS conv_rate
            FROM listings l
            INNER JOIN auctions a ON a.listing_id = l.id
                AND a.ended_at >= NOW() - INTERVAL '90 days'
                AND a.status = 'completed'
            WHERE l.user_id = :uid
              AND l.is_deleted = FALSE
            GROUP BY l.category
            HAVING COUNT(a.id) > 0
            ORDER BY conv_rate DESC, total_auctions DESC
        """), {"uid": UID})).fetchall()

        if cb:
            print(f"  {'Kategori':<15}  {'Toplam':>7}  {'Kazanılan':>10}  {'Ort.Fiyat':>10}  {'Dönüşüm%':>10}")
            print(f"  {'─'*60}")
            for r in cb:
                conv = round(float(r.conv_rate) * 100, 1)
                print(f"  {(r.category or 'diger'):<15}  {int(r.total_auctions):>7}  {int(r.won_auctions):>10}  {float(r.avg_final_price):>10.0f}₺  {conv:>10.1f}%")
        else:
            print("  (Son 90 günde tamamlanmış açık artırma yok)")

        # ── Diagnostik: neden boş? ────────────────────────────────────────
        sep("DIAGNOSTIK — auction tablosundaki verinin durumu")
        diag = (await db.execute(text("""
            SELECT
                a.id,
                a.status,
                a.listing_id,
                a.stream_id,
                a.winner_id,
                a.ended_at,
                l.user_id AS listing_owner
            FROM auctions a
            JOIN live_streams ls ON ls.id = a.stream_id
            LEFT JOIN listings l ON l.id = a.listing_id
            WHERE ls.host_id = :uid
            ORDER BY a.id DESC
            LIMIT 10
        """), {"uid": UID})).fetchall()

        print(f"  {'ID':>5}  {'status':<10}  {'listing_id':>10}  {'stream_id':>9}  {'winner_id':>9}  {'ended_at':>22}  {'owner':>6}")
        print(f"  {'─'*75}")
        for r in diag:
            ea = str(r.ended_at)[:19] if r.ended_at else "NULL"
            lid = str(r.listing_id) if r.listing_id else "NULL"
            wid = str(r.winner_id) if r.winner_id else "NULL"
            owner = str(r.listing_owner) if r.listing_owner else "NULL"
            print(f"  {r.id:>5}  {(r.status or '—'):<10}  {lid:>10}  {r.stream_id:>9}  {wid:>9}  {ea:>22}  {owner:>6}")

        # Filtre bazlı sayım
        cnt_status = (await db.execute(text("""
            SELECT COUNT(*) FROM auctions a
            JOIN live_streams ls ON ls.id = a.stream_id
            WHERE ls.host_id = :uid AND a.status = 'completed'
        """), {"uid": UID})).scalar()

        cnt_listing = (await db.execute(text("""
            SELECT COUNT(*) FROM auctions a
            JOIN live_streams ls ON ls.id = a.stream_id
            WHERE ls.host_id = :uid AND a.listing_id IS NOT NULL
        """), {"uid": UID})).scalar()

        cnt_ended_at = (await db.execute(text("""
            SELECT COUNT(*) FROM auctions a
            JOIN live_streams ls ON ls.id = a.stream_id
            WHERE ls.host_id = :uid
              AND a.ended_at >= NOW() - INTERVAL '90 days'
        """), {"uid": UID})).scalar()

        cnt_all_filters = (await db.execute(text("""
            SELECT COUNT(*) FROM auctions a
            JOIN live_streams ls ON ls.id = a.stream_id
            JOIN listings l ON l.id = a.listing_id
            WHERE ls.host_id = :uid
              AND a.status = 'completed'
              AND a.ended_at >= NOW() - INTERVAL '90 days'
              AND l.user_id = :uid
        """), {"uid": UID})).scalar()

        print(f"\n  Filtre sayımları (toplam {int(stats.total_auctions)} auction):")
        print(f"  status='ended'           : {cnt_status}")
        print(f"  listing_id IS NOT NULL   : {cnt_listing}")
        print(f"  ended_at son 90 günde    : {cnt_ended_at}")
        print(f"  Tüm filtreler birlikte   : {cnt_all_filters}  ← conversion-breakdown bu sayıyı görmeli")

    print()


asyncio.run(main())
