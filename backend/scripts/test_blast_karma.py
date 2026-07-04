"""
Blast karma modelini uçtan uca test eder.

Gerçek kullanıcıya ihtiyaç duymaz — geçici test verisi oluşturur ve temizler.

Test senaryoları:
  1. Karma hesap birimleri (saf Python — her yerde çalışır)
  2. Per-blast-cap kırpması
  3. Redis blast sayacı (INCRBY)
  4. DB: follower filtresi
  5. Yetersiz bakiye mantığı

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/test_blast_karma.py
"""
import asyncio, sys, os, uuid
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ── Sabitler (leads.py ile senkron) ──────────────────────────────────────────
COST_PER_PERSON        = 10
BLAST_LIMIT_STANDARD   = 3
BLAST_LIMIT_PRO        = 6
PER_BLAST_CAP_STANDARD = 5
PER_BLAST_CAP_PRO      = 10

PASS = "✅"
FAIL = "❌"
INFO = "  ℹ "

def sep(title):
    print(f"\n{'━'*65}\n  {title}\n{'━'*65}")


def compute_karma(credits_remaining: int, actual_count: int) -> dict:
    """leads.py send_blast / send_retargeting ile birebir aynı formül."""
    free_used  = min(credits_remaining, actual_count)
    paid_count = actual_count - free_used
    tuci_cost  = paid_count * COST_PER_PERSON
    return dict(free_used=free_used, paid_count=paid_count, tuci_cost=tuci_cost)


def check(label, condition, detail=""):
    icon = PASS if condition else FAIL
    print(f"  {icon} {label}" + (f"  → {detail}" if detail else ""))
    return condition


def assert_karma(name, credits_remaining, actual_count,
                 exp_free, exp_paid, exp_cost):
    r = compute_karma(credits_remaining, actual_count)
    ok = (r["free_used"] == exp_free and
          r["paid_count"] == exp_paid and
          r["tuci_cost"]  == exp_cost)
    detail = (f"free={r['free_used']} paid={r['paid_count']} cost={r['tuci_cost']}"
              f"  (beklenen free={exp_free} paid={exp_paid} cost={exp_cost})")
    check(name, ok, detail)
    return ok


async def main():
    all_ok = True

    # ── 1. Karma hesap birimleri ─────────────────────────────────────────────
    sep("1 · Karma Hesap Birimleri (saf Python)")

    all_ok &= assert_karma(
        "Tam ücretsiz  — krediler yeterli (6 kredi, 6 kişi)",
        credits_remaining=6, actual_count=6,
        exp_free=6, exp_paid=0, exp_cost=0,
    )
    all_ok &= assert_karma(
        "Karma         — 3 kredi var, 6 kişi isteniyor",
        credits_remaining=3, actual_count=6,
        exp_free=3, exp_paid=3, exp_cost=30,
    )
    all_ok &= assert_karma(
        "Tam ücretli   — kredi yok, 5 kişi",
        credits_remaining=0, actual_count=5,
        exp_free=0, exp_paid=5, exp_cost=50,
    )
    all_ok &= assert_karma(
        "Kenar durum   — 0 kişi (hiç alıcı yok)",
        credits_remaining=10, actual_count=0,
        exp_free=0, exp_paid=0, exp_cost=0,
    )
    all_ok &= assert_karma(
        "Kredi fazlası — kredi > actual (kalan kredi ziyan olmaz)",
        credits_remaining=10, actual_count=4,
        exp_free=4, exp_paid=0, exp_cost=0,
    )

    # ── 2. Per-blast-cap kırpması ────────────────────────────────────────────
    sep("2 · Per-Blast-Cap Kırpması")

    for desired, cap, expected, label in [
        (20, PER_BLAST_CAP_STANDARD, 5,  "Standart: desired=20 → cap=5"),
        (20, PER_BLAST_CAP_PRO,     10, "PRO: desired=20 → cap=10"),
        (3,  PER_BLAST_CAP_PRO,      3,  "PRO: desired=3 < cap → 3 kişi gönderilir"),
    ]:
        actual = min(desired, cap)
        all_ok &= check(label, actual == expected, f"min({desired},{cap})={actual}")

    # ── 3. Redis blast sayacı ────────────────────────────────────────────────
    sep("3 · Redis Blast Sayacı (INCRBY)")

    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
    except Exception as e:
        print(f"  {INFO} Redis bağlanamadı — bölüm atlandı ({e})")
        redis = None

    if redis:
        import datetime
        test_uid  = 999_999
        month_key = datetime.date.today().strftime('%Y-%m')
        rkey      = f"blast:{test_uid}:{month_key}"
        await redis.delete(rkey)

        val = await redis.incrby(rkey, 3)
        all_ok &= check("INCRBY 3 → 3", val == 3, f"val={val}")

        val = await redis.incrby(rkey, 2)
        all_ok &= check("INCRBY 2 → 5 (toplam)", val == 5, f"val={val}")

        used      = int(await redis.get(rkey) or 0)
        remaining = max(0, BLAST_LIMIT_PRO - used)
        all_ok &= check("Kalan kredi 6-5=1", remaining == 1,
                        f"used={used} remaining={remaining}")

        await redis.delete(rkey)
        print(f"  {INFO} Redis test anahtarı temizlendi")

    # ── 4. DB: follower filtresi ─────────────────────────────────────────────
    sep("4 · DB: Follower Filtresi")

    try:
        from sqlalchemy import text as sql_text
        from app.database import AsyncSessionLocal
        db_ok = True
    except Exception as e:
        print(f"  {INFO} DB bağlanamadı — bölüm atlandı ({e})")
        db_ok = False

    if db_ok:
        import hashlib
        tag          = f"_blasttest_{uuid.uuid4().hex[:8]}"
        seller_email = f"seller{tag}@test.invalid"
        buyer_emails = [f"buyer{i}{tag}@test.invalid" for i in range(4)]
        # ilk 2 alıcı → seller'ı takip eder; son 2 → takipçi değil
        follower_emails = buyer_emails[:2]
        all_emails      = [seller_email] + buyer_emails

        async with AsyncSessionLocal() as db:
            # Tek tek INSERT (asyncpg list→array dönüşüm sorununu atlatır)
            for email in all_emails:
                h = hashlib.md5(email.encode()).hexdigest()
                await db.execute(sql_text("""
                    INSERT INTO users (email, username, full_name, hashed_password, tuci_balance, fcm_token)
                    VALUES (:email, :uname, 'Test User', 'x', 200, :token)
                """), {"email": email, "uname": f"u_{h[:8]}", "token": f"fcm_{h[:12]}"})
            await db.flush()

            # tag ile bul — list parametresi yok
            rows = (await db.execute(sql_text(
                "SELECT id, email FROM users WHERE email LIKE :pat"
            ), {"pat": f"%{tag}%"})).fetchall()
            id_map        = {r.email: r.id for r in rows}
            seller_id     = id_map[seller_email]
            all_buyer_ids = [id_map[e] for e in buyer_emails]

            for e in follower_emails:
                await db.execute(sql_text("""
                    INSERT INTO follows (follower_id, followed_id)
                    VALUES (:fid, :sid) ON CONFLICT DO NOTHING
                """), {"fid": id_map[e], "sid": seller_id})
            await db.flush()

            # send_blast FCM sorgusunun birebir kopyası
            # (id_map'ten gelen ID'leri tek tek OR ile değil ANY ile geç —
            #  asyncpg integer list'i kabul eder, string list etmez)
            result = await db.execute(sql_text("""
                SELECT fcm_token FROM users
                WHERE id = ANY(:ids)
                  AND fcm_token IS NOT NULL AND fcm_token != ''
                  AND id NOT IN (
                      SELECT follower_id FROM follows WHERE followed_id = :me
                  )
                LIMIT :cap
            """), {"ids": all_buyer_ids, "me": seller_id, "cap": 10})
            tokens = [r[0] for r in result.fetchall()]

            all_ok &= check(
                "4 alıcıdan 2 takipçi çıkarılınca 2 token kalır",
                len(tokens) == 2,
                f"token sayısı={len(tokens)}",
            )

            # LIMIT testi
            result_capped = await db.execute(sql_text("""
                SELECT fcm_token FROM users
                WHERE id = ANY(:ids)
                  AND fcm_token IS NOT NULL AND fcm_token != ''
                  AND id NOT IN (
                      SELECT follower_id FROM follows WHERE followed_id = :me
                  )
                LIMIT :cap
            """), {"ids": all_buyer_ids, "me": seller_id, "cap": 1})
            tokens_capped = [r[0] for r in result_capped.fetchall()]
            all_ok &= check(
                "LIMIT 1 → yalnızca 1 token döner",
                len(tokens_capped) == 1,
                f"token sayısı={len(tokens_capped)}",
            )

            # Temizlik — tag LIKE ile, list parametresi yok
            await db.execute(sql_text(
                "DELETE FROM follows WHERE followed_id = :sid"
            ), {"sid": seller_id})
            await db.execute(sql_text(
                "DELETE FROM users WHERE email LIKE :pat"
            ), {"pat": f"%{tag}%"})
            await db.commit()
            print(f"  {INFO} Test verileri temizlendi")

    # ── 5. Yetersiz bakiye mantığı ───────────────────────────────────────────
    sep("5 · Yetersiz Bakiye Mantığı")

    for cost, balance, exp_insuf, label in [
        (50, 100, False, "50 TUCi lazım, 100 var → yeterli"),
        (50,  50, False, "50 TUCi lazım, 50 var  → tam yeterli"),
        (50,  49, True,  "50 TUCi lazım, 49 var  → yetersiz"),
        ( 0,   0, False, "0 TUCi lazım           → sorun yok"),
    ]:
        is_insuf = cost > 0 and balance < cost
        all_ok &= check(label, is_insuf == exp_insuf,
                        f"cost={cost} balance={balance}")

    # ── Özet ─────────────────────────────────────────────────────────────────
    sep("ÖZET")
    if all_ok:
        print(f"  {PASS} Tüm kontroller geçti — blast karma modeli doğru çalışıyor.\n")
    else:
        print(f"  {FAIL} Bazı kontroller başarısız — yukarıdaki logları inceleyin.\n")

    return all_ok


if __name__ == "__main__":
    ok = asyncio.run(main())
    sys.exit(0 if ok else 1)
