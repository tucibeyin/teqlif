"""
Rakip Radarı ekranı verilerini doğrular (competitor-radar + category-velocity).
İlk aktif ilanı otomatik seçer; argüman ile override edilebilir.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/competitor_radar_check.py [user_id] [listing_id]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UID        = int(sys.argv[1]) if len(sys.argv) > 1 else 3
LISTING_ID = int(sys.argv[2]) if len(sys.argv) > 2 else None


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:

        # ── Hedef ilanı bul ───────────────────────────────────────────────
        q = select(Listing).where(
            Listing.user_id == UID,
            Listing.is_active == True,  # noqa
            Listing.is_deleted == False,  # noqa
            Listing.price.is_not(None),
        )
        if LISTING_ID:
            q = q.where(Listing.id == LISTING_ID)
        else:
            q = q.limit(1)

        listing = (await db.execute(q)).scalar_one_or_none()
        if not listing:
            print("Aktif ilan bulunamadı."); return

        sep(f"HEDEF İLAN #{listing.id}: {listing.title}")
        print(f"  Kategori  : {listing.category}")
        print(f"  Fiyat     : {int(listing.price or 0)}₺")
        print(f"  Embedding : {'✓' if listing.embedding is not None else '✗ YOK'}")

        # ── 1. Competitor Radar ───────────────────────────────────────────
        sep("1. RAKİP RADARI  (competitor-radar)")

        if listing.embedding is not None:
            vec_literal = "'" + "[" + ",".join(f"{x:.8f}" for x in listing.embedding) + "]" + "'::vector"
            rows = (await db.execute(text(f"""
                SELECT l.id, l.title, l.category, l.price,
                       (l.embedding <=> {vec_literal}) AS dist
                FROM listings l
                WHERE l.is_active = TRUE AND l.is_deleted = FALSE
                  AND l.embedding IS NOT NULL
                  AND l.id != :lid AND l.user_id != :uid
                  AND l.price IS NOT NULL
                  AND (l.embedding <=> {vec_literal}) < 0.45
                ORDER BY l.embedding <=> {vec_literal}
                LIMIT 20
            """), {"lid": listing.id, "uid": UID})).fetchall()
        else:
            rows = (await db.execute(text("""
                SELECT id, title, category, price, NULL AS dist
                FROM listings
                WHERE is_active = TRUE AND is_deleted = FALSE
                  AND category = :cat AND id != :lid AND user_id != :uid
                  AND price IS NOT NULL
                ORDER BY ABS(price - :price) ASC
                LIMIT 20
            """), {"cat": listing.category, "lid": listing.id,
                   "uid": UID, "price": float(listing.price)})).fetchall()

        if not rows:
            print("  ⚠ Benzer rakip ilan bulunamadı (embedding < 0.45 veya kategori eşleşmesi yok)")
        else:
            prices = [float(r.price) for r in rows]
            my_price = float(listing.price)
            avg_price = sum(prices) / len(prices)
            cheaper = sum(1 for p in prices if p < my_price)
            pct_rank = round((cheaper / len(prices)) * 100)

            if pct_rank >= 75:
                signal = "pahalı"
            elif pct_rank <= 25:
                signal = "ucuz"
            else:
                signal = "uygun"

            print(f"  Rakip sayısı  : {len(rows)}")
            print(f"  Benim fiyatım : {my_price:.0f}₺")
            print(f"  Ortalama fiyat: {avg_price:.0f}₺  (min {min(prices):.0f}₺ / maks {max(prices):.0f}₺)")
            print(f"  Fiyat sırası  : %{pct_rank} (rakiplerin %{cheaper}'i daha ucuz)")
            print(f"  Sinyal        : {signal}")

            print(f"\n  {'ID':>5}  {'dist':>6}  {'fiyat':>8}  {'kategori':<14}  Başlık")
            print(f"  {'─'*60}")
            for r in rows[:10]:
                dist_str = f"{float(r.dist):.3f}" if r.dist is not None else "  —  "
                cat_match = "✓" if r.category == listing.category else "✗"
                print(f"  {r.id:>5}  {dist_str:>6}  {int(r.price):>8}₺  {cat_match} {(r.category or ''):<12}  {(r.title or '')[:28]}")

        # ── 2. Category Velocity ──────────────────────────────────────────
        sep(f"2. SATIŞ HIZI  (category-velocity, kategori: {listing.category})")

        vel = (await db.execute(text("""
            SELECT
                COUNT(*) AS total_sold,
                ROUND(AVG(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS avg_days,
                ROUND(MIN(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS min_days,
                ROUND(MAX(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS max_days,
                ROUND(AVG(l.price)::numeric, 0) AS avg_price,
                ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY l.price)::numeric, 0) AS p25_price,
                ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY l.price)::numeric, 0) AS p75_price
            FROM auctions a
            INNER JOIN listings l ON l.id = a.listing_id
            WHERE a.status = 'completed'
              AND a.winner_username IS NOT NULL
              AND a.ended_at IS NOT NULL
              AND l.category = :cat
              AND a.ended_at > NOW() - INTERVAL '90 days'
              AND l.price IS NOT NULL
        """), {"cat": listing.category})).fetchone()

        total_sold = int(vel[0]) if vel and vel[0] else 0
        avg_days   = float(vel[1]) if vel and vel[1] else None

        print(f"  Son 90 gün satış sayısı: {total_sold}")
        if total_sold == 0:
            print("  ⚠ listing_id'li tamamlanmış auction yok — veri üretilemez")
            print("  (Manuel giriş açık artırmalarında listing_id kaydedilmez)")
        else:
            print(f"  Ort. satış süresi: {avg_days:.1f} gün")
            print(f"  Min–Maks: {float(vel[2]):.1f} – {float(vel[3]):.1f} gün")
            print(f"  Ort. fiyat: {float(vel[4]):.0f}₺  (P25={float(vel[5]):.0f}₺ / P75={float(vel[6]):.0f}₺)")

        active_count = (await db.execute(text("""
            SELECT COUNT(*) FROM listings
            WHERE category = :cat AND is_active = TRUE AND is_deleted = FALSE
              AND id != :lid
        """), {"cat": listing.category, "lid": listing.id})).scalar()
        print(f"  Şu an aktif rakip ilan sayısı: {active_count}")

    print()


asyncio.run(main())
