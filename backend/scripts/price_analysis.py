"""
'Fiyatın Piyasada Nerede' verisini adım adım gösterir.
Hangi benzer ilanlar bulundu, embedding mesafesi nedir, IQR filtresi ne yaptı.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/price_analysis.py <listing_id>
"""
import asyncio, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LISTING_ID = int(sys.argv[1]) if len(sys.argv) > 1 else 2


async def main():
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        # ── 1. Hedef ilanı al ─────────────────────────────────────────────
        listing = (await db.execute(
            select(Listing).where(Listing.id == LISTING_ID)
        )).scalar_one_or_none()
        if not listing:
            print(f"İlan {LISTING_ID} bulunamadı."); return

        print(f"\n{'━'*70}")
        print(f"  HEDEF İLAN #{listing.id}: {listing.title}")
        print(f"  Kategori: {listing.category}  |  Fiyat: {listing.price}₺")
        print(f"  Embedding var mı: {'✓' if listing.embedding is not None else '✗ YOK'}")
        print(f"{'━'*70}")

        if listing.embedding is None:
            print("\n  ⚠ Bu ilan için embedding yok — fiyat tahmini çalışamaz.")
            print("  Embedding, ilan oluşturulduğunda/güncellendiğinde ml_service ile üretilir.\n")
            # Embeddingi olmayan ilanlar için ne kadar tamamlanmış açık artırma var göster
            total_auctions = (await db.execute(
                text("SELECT count(*) FROM auctions WHERE winner_username IS NOT NULL AND final_price > 0")
            )).scalar()
            print(f"  Sistemdeki tamamlanmış açık artırma sayısı: {total_auctions}")
            return

        # ── 2. pgvector aday havuzu (dist < 0.55) ────────────────────────
        emb_str = "[" + ",".join(f"{v:.6f}" for v in listing.embedding) + "]"

        rows = (await db.execute(text("""
            SELECT
                l.id,
                l.title,
                l.category,
                l.location,
                l.created_at,
                a.start_price,
                a.final_price,
                a.winner_username,
                (l.embedding <=> CAST(:emb AS vector)) AS dist
            FROM listings l
            JOIN auctions a ON a.listing_id = l.id
            WHERE a.winner_username IS NOT NULL
              AND l.embedding IS NOT NULL
              AND a.final_price > 0
              AND (l.embedding <=> CAST(:emb AS vector)) < 0.55
            ORDER BY dist
            LIMIT 150
        """), {"emb": emb_str})).fetchall()

        print(f"\n[1] pgvector aday havuzu (dist < 0.55): {len(rows)} ilan bulundu")
        if not rows:
            print("  ⚠ Hiç benzer tamamlanmış ilan bulunamadı — fiyat tahmini 'veri yok' döner.")
            # Tüm açık artırma sayısını göster
            total = (await db.execute(
                text("SELECT count(*) FROM auctions WHERE winner_username IS NOT NULL AND final_price > 0")
            )).scalar()
            print(f"  Sistemdeki tamamlanmış açık artırma: {total}")
            return

        # ── 3. Composite score hesapla ────────────────────────────────────
        body_category = (listing.category or "").lower()
        body_city = ""  # listing.location'dan şehir çıkarılabilir ama şimdilik boş

        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)

        scored = []
        for row in rows:
            sem_sim = max(0.0, 1.0 - float(row.dist))
            cat_mult = 2.0 if (row.category or "").lower() == body_category else 1.0
            city_mult = 1.0
            created = row.created_at
            if created and created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            age_days = max(0, (now - created).days) if created else 0
            recency = math.exp(-age_days / 180.0)
            composite = sem_sim * cat_mult * city_mult * recency
            scored.append((composite, row))

        scored.sort(key=lambda x: x[0], reverse=True)

        print(f"\n[2] Composite score sonrası ilk 20 (sem_sim × kategori × güncellik):")
        print(f"  {'ID':>5}  {'dist':>6}  {'score':>6}  {'cat':>12}  {'final₺':>8}  Başlık")
        print(f"  {'─'*65}")
        for score, row in scored[:20]:
            cat_match = "✓" if (row.category or "").lower() == body_category else "—"
            print(f"  {row.id:>5}  {float(row.dist):>6.3f}  {score:>6.3f}  {cat_match} {(row.category or ''):<10}  {int(row.final_price):>8}  {(row.title or '')[:30]}")

        # ── 4. IQR filtresi ───────────────────────────────────────────────
        top_pre = scored[:30]
        prices_pre = sorted(float(r.final_price) for _, r in top_pre)
        n_p = len(prices_pre)

        print(f"\n[3] IQR filtresi (ilk 30 üzerinde, >= 10 veri noktasında uygulanır):")
        print(f"  Veri sayısı: {n_p}")
        if n_p >= 10:
            q1 = prices_pre[n_p // 4]
            q3 = prices_pre[(3 * n_p) // 4]
            iqr = q3 - q1
            lo = q1 - 1.5 * iqr
            hi = q3 + 1.5 * iqr
            filtered = [(s, r) for s, r in top_pre if lo <= float(r.final_price) <= hi]
            print(f"  Q1={q1:.0f}₺  Q3={q3:.0f}₺  IQR={iqr:.0f}  Aralık: {lo:.0f}₺ – {hi:.0f}₺")
            print(f"  Filtre öncesi: {len(top_pre)}  →  Sonrası: {len(filtered)}")
        else:
            filtered = top_pre
            print(f"  Veri < 10, IQR uygulanmadı")

        top = filtered
        cnt = len(top)

        # ── 5. Sonuç ─────────────────────────────────────────────────────
        print(f"\n[4] Fiyat hesabı (ağırlıklı ortalama):")
        if cnt == 0:
            print("  Filtreleme sonrası 0 veri — tahmin üretilemez.")
            return

        total_w = sum(s for s, _ in top)
        w_final = sum(s * float(r.final_price) for s, r in top) / total_w
        all_finals = sorted(float(r.final_price) for _, r in top)
        n = len(all_finals)
        min_price = all_finals[max(0, n // 10)]
        max_price = all_finals[min(n - 1, max(0, n - n // 10 - 1))]
        cat_matched = sum(1 for _, r in top if (r.category or "").lower() == body_category)

        if cat_matched >= 10 or (cat_matched >= 5 and body_category):
            confidence = "high"
        elif cat_matched >= 3 or cnt >= 10:
            confidence = "medium"
        else:
            confidence = "low"

        print(f"  Kullanılan veri: {cnt}  |  Kategori eşleşmesi: {cat_matched}")
        print(f"  Tahmini kapanış (ağırlıklı): {w_final:.0f}₺")
        print(f"  Min–Max aralığı: {min_price:.0f}₺ – {max_price:.0f}₺")
        print(f"  Güven seviyesi: {confidence}")
        print(f"\n  Hedef ilanın fiyatı: {listing.price}₺")
        if listing.price and w_final > 0:
            diff = ((listing.price - w_final) / w_final) * 100
            print(f"  Piyasa ortalamasına göre: %{diff:+.1f}")

    # ── 6. Pro Insights: price_intel (aktif ilanlar karşılaştırması) ───────────
    # Bu Satış ve Kitle Raporu → 'Fiyatın Piyasada Nerede' bölümünün kaynağı
    print(f"\n{'━'*70}")
    print(f"  [5] PRICE_INTEL — Aktif ilanlar karşılaştırması")
    print(f"  (Satış ve Kitle Raporu 'Fiyatın Piyasada Nerede' kaynağı)")
    print(f"{'━'*70}")

    async with AsyncSessionLocal() as db2:
        listing2 = (await db2.execute(
            select(Listing).where(Listing.id == LISTING_ID)
        )).scalar_one_or_none()

        if listing2 and listing2.embedding is not None:
            emb2 = "[" + ",".join(f"{x:.6f}" for x in listing2.embedding) + "]"
            price_lo = float(listing2.price or 1) * 0.05
            price_hi = float(listing2.price or 1) * 20.0

            # Embedding benzerliğiyle bulunan aktif ilanlar (eski query — kategorisiz, filtre yok)
            sim_rows = (await db2.execute(text("""
                SELECT id, title, category, price, user_id,
                       (embedding <=> CAST(:emb AS vector)) AS dist
                FROM listings
                WHERE user_id != :uid
                  AND is_active AND NOT is_deleted
                  AND price IS NOT NULL
                  AND embedding IS NOT NULL
                ORDER BY embedding <=> CAST(:emb AS vector)
                LIMIT 10
            """), {"uid": listing2.user_id, "emb": emb2})).fetchall()

            print(f"\n  Embedding benzerliğiyle bulunan ilk 10 aktif ilan (mevcut query):")
            print(f"  {'ID':>5}  {'dist':>6}  {'fiyat':>8}  {'kategori':<14}  Başlık")
            print(f"  {'─'*60}")
            prices = []
            for r in sim_rows:
                cat_match = "✓" if r.category == listing2.category else "✗"
                print(f"  {r.id:>5}  {float(r.dist):>6.3f}  {int(r.price):>8}₺  {cat_match} {(r.category or ''):<12}  {(r.title or '')[:28]}")
                prices.append(float(r.price))

            if prices:
                avg = sum(prices) / len(prices)
                print(f"\n  Market_avg (mevcut): {avg:.0f}₺")
                if listing2.price:
                    diff = ((listing2.price - avg) / avg) * 100
                    print(f"  İlan fiyatı: {listing2.price}₺  →  Piyasaya göre: %{diff:+.1f}")

            # Kategori + fiyat filtreli versiyon (düzeltilmiş — production'daki yeni query)
            sim_cat_rows = (await db2.execute(text("""
                SELECT id, title, category, price,
                       (embedding <=> CAST(:emb AS vector)) AS dist
                FROM listings
                WHERE user_id != :uid
                  AND category = :cat
                  AND is_active AND NOT is_deleted
                  AND price > :lo AND price < :hi
                  AND embedding IS NOT NULL
                ORDER BY embedding <=> CAST(:emb AS vector)
                LIMIT 10
            """), {"uid": listing2.user_id, "emb": emb2, "cat": listing2.category,
                   "lo": price_lo, "hi": price_hi})).fetchall()

            print(f"\n  Kategori + fiyat filtreli versiyon (düzeltilmiş — {listing2.category}, {price_lo:.0f}₺–{price_hi:.0f}₺):")
            cat_prices = []
            for r in sim_cat_rows:
                print(f"  {r.id:>5}  {float(r.dist):>6.3f}  {int(r.price):>8}₺  {(r.title or '')[:30]}")
                cat_prices.append(float(r.price))
            if cat_prices:
                cat_avg = sum(cat_prices) / len(cat_prices)
                print(f"\n  Market_avg (kategori filtreli): {cat_avg:.0f}₺")
            else:
                print(f"  (Aynı kategoride başka aktif ilan yok)")
        else:
            print("  Embedding yok — price_intel çalışamaz.")
    print()


asyncio.run(main())
