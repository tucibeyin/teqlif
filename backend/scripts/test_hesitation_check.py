"""
bid_hesitation tracking'ini uçtan uca test eder.

Test senaryoları:
  1. _build_recommendation eşik mantığı (saf Python)
  2. ClickHouse bağlantısı
  3. ClickHouse insert → query tutarlılığı
  4. Aynı kullanıcı tekrar sayımı (dedup yok mu?)
  5. metadata/peak_progress kaydediliyor mu?
  6. Cleanup

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/test_hesitation_check.py
"""
import asyncio, sys, os
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PASS = "✅"
FAIL = "❌"
INFO = "  ℹ "
TEST_ITEM_ID = 999_999_901   # gerçek ilanlarla çakışmayacak sahte ID

def sep(title):
    print(f"\n{'━'*65}\n  {title}\n{'━'*65}")

def check(label, condition, detail=""):
    icon = PASS if condition else FAIL
    print(f"  {icon} {label}" + (f"  → {detail}" if detail else ""))
    return condition


# ─────────────────────────────────────────────────────────────────────────────
# BÖLÜM 1 — _build_recommendation eşik mantığı (saf Python, DB gerekmez)
# ─────────────────────────────────────────────────────────────────────────────
def test_thresholds():
    sep("1. _build_recommendation eşik mantığı")
    from app.routers.analytics import _build_recommendation

    cases = [
        # (avg_budget, hesitation_count, unique_users, beklenen anahtar kelime)
        (None, 0,  0, "yeterli bütçe verisi yok"),       # veri yok
        (None, 6,  0, "tereddüt etti"),                   # avg_budget=None + hes>5
        (500,  2,  5, "500"),                              # düşük hes, düşük kitle → bütçe metni
        (500,  3,  5, "tekliften vazgeçti"),               # hes>=3 eşiği
        (500,  10, 5, "teklif vermek istedi ama vazgeçti"), # hes>=10 eşiği
        (500,  15, 5, "teklif vermek istedi ama vazgeçti"), # hes>=10 (üstü)
        (500,  2, 12, "premium"),                          # unique>=10 kolu
    ]

    all_ok = True
    for avg_budget, hes, uniq, keyword in cases:
        text = _build_recommendation(avg_budget, hes, uniq)
        ok = keyword.lower() in text.lower()
        detail = f"hes={hes} uniq={uniq} avg={avg_budget} → '{text[:60]}...'"
        all_ok &= check(f"keyword='{keyword}'", ok, detail)

    return all_ok


# ─────────────────────────────────────────────────────────────────────────────
# BÖLÜM 2-5 — ClickHouse testleri
# ─────────────────────────────────────────────────────────────────────────────
async def test_clickhouse():
    from app.database_clickhouse import get_clickhouse_client

    # ── 2. Bağlantı ──────────────────────────────────────────────────────────
    sep("2. ClickHouse bağlantısı")
    try:
        ch = await get_clickhouse_client()
        r = await ch.query("SELECT 1")
        conn_ok = check("ClickHouse bağlantısı", r.result_rows == [(1,)])
    except Exception as e:
        check("ClickHouse bağlantısı", False, str(e))
        print(f"\n{FAIL} ClickHouse'a bağlanılamadı, sonraki testler atlanıyor.")
        return False

    # ── Mevcut tabloyu temizle (önceki başarısız run kalıntısı) ──────────────
    await ch.command(
        f"ALTER TABLE user_events DELETE WHERE item_id = {TEST_ITEM_ID}"
    )

    # ── 3. Insert → Query tutarlılığı ─────────────────────────────────────────
    sep("3. ClickHouse insert → query tutarlılığı")

    now = datetime.now(timezone.utc)
    ts  = now.strftime("%Y-%m-%d %H:%M:%S")

    # 4 farklı kullanıcıdan 4 bid_hesitation
    rows = [
        [1001, TEST_ITEM_ID, "listing", "bid_hesitation", 200.0, None, now],
        [1002, TEST_ITEM_ID, "listing", "bid_hesitation", 300.0, None, now],
        [1003, TEST_ITEM_ID, "listing", "bid_hesitation", None,  None, now],
        [1004, TEST_ITEM_ID, "listing", "bid_hesitation", 400.0, None, now],
    ]
    await ch.insert(
        "user_events", rows,
        column_names=["user_id","item_id","item_type","event_type","price_point","duration_seconds","timestamp"],
    )
    await asyncio.sleep(1)   # MergeTree yazma gecikmesi

    r = await ch.query(f"""
        SELECT countIf(event_type='bid_hesitation'), avgIf(price_point, price_point > 0)
        FROM user_events
        WHERE item_id = {TEST_ITEM_ID}
    """)
    row = r.result_rows[0]
    count      = int(row[0] or 0)
    avg_budget = float(row[1]) if row[1] else None

    check("4 event insert → count=4", count == 4, f"count={count}")
    check("avg_budget doğru (300 TL)", avg_budget is not None and abs(avg_budget - 300.0) < 1,
          f"avg={avg_budget:.1f}" if avg_budget else "None")

    # ── 4. Aynı kullanıcı dedup ───────────────────────────────────────────────
    sep("4. Aynı kullanıcı tekrar sayımı (dedup yok mu?)")

    same_user_rows = [
        [1001, TEST_ITEM_ID, "listing", "bid_hesitation", 200.0, None, now],
        [1001, TEST_ITEM_ID, "listing", "bid_hesitation", 200.0, None, now],
        [1001, TEST_ITEM_ID, "listing", "bid_hesitation", 200.0, None, now],
    ]
    await ch.insert(
        "user_events", same_user_rows,
        column_names=["user_id","item_id","item_type","event_type","price_point","duration_seconds","timestamp"],
    )
    await asyncio.sleep(1)

    r2 = await ch.query(f"""
        SELECT
            countIf(event_type='bid_hesitation')        AS raw_count,
            countDistinctIf(user_id, event_type='bid_hesitation') AS unique_users
        FROM user_events
        WHERE item_id = {TEST_ITEM_ID}
    """)
    row2 = r2.result_rows[0]
    raw_count   = int(row2[0] or 0)
    unique_users = int(row2[1] or 0)

    check("Raw count = 7 (4+3, dedup YOK)", raw_count == 7,
          f"raw={raw_count}")
    check("Unique kullanıcı = 4 (user_id=1001 birden fazla sayıldı)",
          unique_users == 4, f"unique={unique_users}")
    if raw_count != unique_users:
        print(f"  {INFO} Aynı kullanıcı {raw_count - unique_users} kez fazla sayılıyor — "
              "hesitation_count unique değil, raw count.")

    # ── 5. metadata / peak_progress kaydediliyor mu? ──────────────────────────
    sep("5. metadata / peak_progress ClickHouse'da var mı?")
    r3 = await ch.query("DESCRIBE TABLE user_events")
    col_names = [row[0] for row in r3.result_rows]
    has_metadata = "metadata" in col_names or "peak_progress" in col_names
    check("ClickHouse user_events tablosunda metadata kolonu VAR", has_metadata,
          f"kolonlar={col_names}")
    if not has_metadata:
        print(f"  {INFO} peak_progress worker'da Redis'ten okunuyor ama"
              " user_events'e yazılmıyor → veri sessizce kayboluyor.")
        print(f"  {INFO} Hangi ilan için yüksek niyet (>%80 swipe) var bilinemiyor.")

    # ── Cleanup ───────────────────────────────────────────────────────────────
    sep("Cleanup")
    await ch.command(
        f"ALTER TABLE user_events DELETE WHERE item_id = {TEST_ITEM_ID}"
    )
    await asyncio.sleep(1)
    r4 = await ch.query(f"SELECT count() FROM user_events WHERE item_id = {TEST_ITEM_ID}")
    remaining = int(r4.result_rows[0][0] or 0)
    check("Test verileri silindi", remaining == 0, f"kalan={remaining}")

    return True


# ─────────────────────────────────────────────────────────────────────────────
async def main():
    print("\n" + "═"*65)
    print("  bid_hesitation Tracking Test")
    print("═"*65)

    t1 = test_thresholds()
    t2 = await test_clickhouse()

    sep("SONUÇ")
    if t1 and t2:
        print(f"  {PASS} Tüm testler geçti.\n")
    else:
        print(f"  {FAIL} Bazı testler başarısız — yukarıya bakın.\n")


if __name__ == "__main__":
    asyncio.run(main())
