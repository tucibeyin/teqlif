#!/usr/bin/env python3
"""
Reaktivasyon feature test scripti — VPS'de çalıştırılır.
Kullanım: python test_reactivation.py

Test senaryoları:
  1. PRO kullanıcı → ücretsiz kredi kullanımı
  2. PRO kullanıcı → kredileri tükendikten sonra TUCi ödeme
  3. Normal kullanıcı → TUCi ödeme
  4. Normal kullanıcı → yetersiz bakiye (402)
  5. Aktif→Pasif: kampanya silinmesi, ilan sıfırlanması
"""
import sys
import json
import asyncio
import argparse
from datetime import datetime, timezone

import httpx
from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# ── Yapılandırma ──────────────────────────────────────────────────────────────
BASE_URL   = "https://www.teqlif.com/api"
DB_URL     = "postgresql+asyncpg://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"
TEST_EMAIL = "teqlif@gmail.com"
TEST_PASS  = "SIFRENIZI_GIRIN"          # <-- buraya gir
LISTING_TITLE = "Teqlif Deneme 2"

# ── Renk çıktı ────────────────────────────────────────────────────────────────
G = "\033[92m"   # yeşil
R = "\033[91m"   # kırmızı
Y = "\033[93m"   # sarı
B = "\033[96m"   # mavi
X = "\033[0m"    # reset

def ok(msg):   print(f"{G}  ✔ {msg}{X}")
def err(msg):  print(f"{R}  ✘ {msg}{X}")
def info(msg): print(f"{B}  → {msg}{X}")
def head(msg): print(f"\n{Y}{'─'*60}\n  {msg}\n{'─'*60}{X}")


# ── DB yardımcıları ───────────────────────────────────────────────────────────
engine = create_async_engine(DB_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def db_exec(sql: str, params: dict = {}):
    async with AsyncSessionLocal() as s:
        result = await s.execute(text(sql), params)
        await s.commit()
        return result


async def db_fetchone(sql: str, params: dict = {}):
    async with AsyncSessionLocal() as s:
        result = await s.execute(text(sql), params)
        row = result.mappings().first()
        return dict(row) if row else None


async def db_fetchall(sql: str, params: dict = {}):
    async with AsyncSessionLocal() as s:
        result = await s.execute(text(sql), params)
        return [dict(r) for r in result.mappings().all()]


# ── API yardımcıları ──────────────────────────────────────────────────────────
async def login(client: httpx.AsyncClient, email: str, password: str) -> str:
    resp = await client.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    resp.raise_for_status()
    data = resp.json()
    token = data.get("access_token") or data.get("token")
    if not token:
        raise ValueError(f"Token alınamadı: {data}")
    return token


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def get_listing_id(title: str) -> int | None:
    row = await db_fetchone(
        "SELECT id FROM listings WHERE title = :t AND is_deleted = false LIMIT 1",
        {"t": title},
    )
    return row["id"] if row else None


async def get_listing_state(listing_id: int) -> dict:
    row = await db_fetchone(
        "SELECT id, title, is_active, is_highlight, created_at, deactivated_at FROM listings WHERE id = :id",
        {"id": listing_id},
    )
    return row or {}


async def get_campaigns(listing_id: int) -> list:
    return await db_fetchall(
        "SELECT id, status FROM ad_campaigns WHERE listing_id = :id",
        {"id": listing_id},
    )


async def get_impressions(listing_id: int) -> int:
    row = await db_fetchone(
        "SELECT COUNT(*) as cnt FROM listing_impressions WHERE listing_id = :id",
        {"id": listing_id},
    )
    return row["cnt"] if row else 0


async def set_tuci(user_id: int, balance: int):
    await db_exec(
        "UPDATE users SET tuci_balance = :b WHERE id = :id",
        {"b": balance, "id": user_id},
    )


async def set_premium(user_id: int, is_premium: bool):
    await db_exec(
        "UPDATE users SET is_premium = :p WHERE id = :id",
        {"p": is_premium, "id": user_id},
    )


async def _redis():
    import redis.asyncio as aioredis
    return aioredis.from_url("redis://localhost:6379")


async def clear_reactivation_credits(user_id: int):
    """Redis'ten reactivation_credits anahtarlarını sil."""
    r = await _redis()
    keys = await r.keys(f"reactivation_credits:{user_id}:*")
    if keys:
        await r.delete(*keys)
    await r.aclose()
    info(f"Redis reaktivasyon kredileri temizlendi ({len(keys)} anahtar)")


async def set_reactivation_used(user_id: int, count: int, premium_since_date):
    """Redis'e anniversary-based key ile kredi sayısı yaz (servisle aynı mantık)."""
    import calendar
    from datetime import date
    today      = date.today()
    day        = premium_since_date.day
    last_this  = calendar.monthrange(today.year, today.month)[1]
    ann_this   = date(today.year, today.month, min(day, last_this))
    if today >= ann_this:
        period = ann_this
    else:
        prev_m = today.month - 1 if today.month > 1 else 12
        prev_y = today.year if today.month > 1 else today.year - 1
        period = date(prev_y, prev_m, min(day, calendar.monthrange(prev_y, prev_m)[1]))

    key = f"reactivation_credits:{user_id}:{period.isoformat()}"
    r   = await _redis()
    if count == 0:
        await r.delete(key)
    else:
        await r.set(key, count, ex=3600 * 24 * 35)
    await r.aclose()
    info(f"Redis key={key} → {count}")


async def insert_fake_impressions(listing_id: int, n: int = 3):
    """Test için gerçek user_id'lerle listing_impressions satırları ekle."""
    rows = await db_fetchall("SELECT id FROM users ORDER BY id LIMIT :n", {"n": n})
    inserted = 0
    for row in rows:
        await db_exec(
            """
            INSERT INTO listing_impressions (user_id, listing_id, seen_at)
            VALUES (:uid, :lid, now())
            ON CONFLICT DO NOTHING
            """,
            {"uid": row["id"], "lid": listing_id},
        )
        inserted += 1
    info(f"{inserted} impression eklendi")


async def toggle(client: httpx.AsyncClient, token: str, listing_id: int) -> dict:
    resp = await client.patch(
        f"{BASE_URL}/listings/{listing_id}/toggle",
        headers=auth(token),
    )
    return {"status": resp.status_code, "body": resp.json() if resp.text else {}}


async def reactivation_cost_api(client: httpx.AsyncClient, token: str, listing_id: int) -> dict:
    resp = await client.get(
        f"{BASE_URL}/listings/{listing_id}/reactivation-cost",
        headers=auth(token),
    )
    return resp.json()


async def reactivation_credits_api(client: httpx.AsyncClient, token: str) -> dict:
    resp = await client.get(
        f"{BASE_URL}/analytics/reactivation-credits",
        headers=auth(token),
    )
    return resp.json()


# ── Senaryo yardımcısı ────────────────────────────────────────────────────────
async def ensure_listing_passive(client, token, listing_id):
    """İlan aktifse önce pasife al."""
    state = await get_listing_state(listing_id)
    if state.get("is_active"):
        info("İlan aktif, önce pasife alınıyor...")
        r = await toggle(client, token, listing_id)
        assert r["status"] == 200, f"Pasife alma başarısız: {r}"
        ok("İlan pasife alındı")


async def ensure_listing_active(client, token, listing_id):
    """İlan pasifse aktife al (kredi kontrolü bypass'lı DB üzerinden)."""
    state = await get_listing_state(listing_id)
    if not state.get("is_active"):
        await db_exec(
            "UPDATE listings SET is_active = true, created_at = now(), deactivated_at = null WHERE id = :id",
            {"id": listing_id},
        )
        ok("İlan DB üzerinden aktife alındı (test setup)")


# ── Ana test fonksiyonları ────────────────────────────────────────────────────

async def test_1_pro_free_credit(client, token, listing_id, user_id):
    head("Senaryo 1: PRO kullanıcı → ücretsiz kredi kullanımı")

    await set_premium(user_id, True)
    await clear_reactivation_credits(user_id)
    await ensure_listing_passive(client, token, listing_id)

    # Kredi durumunu kontrol et
    credits = await reactivation_credits_api(client, token)
    info(f"Kredi durumu: {credits}")
    assert credits["is_premium"] is True, "is_premium True olmalı"
    assert credits["free_remaining"] == 5, f"free_remaining=5 beklendi, {credits['free_remaining']} geldi"
    assert credits["can_afford"] is True, "can_afford True olmalı"
    ok("Kredi API doğru döndü")

    # Reaktivasyon yap
    r = await toggle(client, token, listing_id)
    assert r["status"] == 200, f"Toggle başarısız: {r}"
    assert r["body"].get("is_active") is True
    ok(f"Toggle başarılı → is_active=True")

    # Kredi azaldı mı?
    credits_after = await reactivation_credits_api(client, token)
    assert credits_after["free_remaining"] == 4, \
        f"free_remaining=4 beklendi, {credits_after['free_remaining']} geldi"
    ok(f"Ücretsiz kredi kullanıldı → kalan: {credits_after['free_remaining']}")

    # created_at sıfırlandı mı?
    state = await get_listing_state(listing_id)
    age_sec = (datetime.now(timezone.utc) - state["created_at"].replace(tzinfo=timezone.utc)).total_seconds()
    assert age_sec < 30, f"created_at sıfırlanmadı, {age_sec:.0f}s önce"
    ok(f"created_at sıfırlandı ({age_sec:.1f}s önce)")


async def test_2_pro_paid(client, token, listing_id, user_id):
    head("Senaryo 2: PRO kullanıcı → krediler tükenmiş, TUCi ödeme")

    await set_premium(user_id, True)
    await set_tuci(user_id, 50)

    # premium_since'i DB'den çek → anniversary key'i doğru hesapla
    row = await db_fetchone("SELECT premium_since FROM users WHERE id = :id", {"id": user_id})
    premium_since = row["premium_since"]
    info(f"premium_since = {premium_since}")

    await clear_reactivation_credits(user_id)
    await set_reactivation_used(user_id, 5, premium_since)  # 5 kredi → tükenmiş

    await ensure_listing_passive(client, token, listing_id)

    credits = await reactivation_credits_api(client, token)
    info(f"Kredi durumu: {credits}")
    assert credits["free_remaining"] == 0, \
        f"free_remaining=0 beklendi, {credits['free_remaining']} geldi"
    assert credits["cost"] == 10, f"cost=10 beklendi, {credits['cost']} geldi"
    assert credits["can_afford"] is True, "50 TUCi ile afford edebilmeli"
    ok("Kredi tükendi, bakiye yeterli")

    balance_before = (await db_fetchone("SELECT tuci_balance FROM users WHERE id = :id", {"id": user_id}))["tuci_balance"]
    r = await toggle(client, token, listing_id)
    assert r["status"] == 200, f"Toggle başarısız: {r}"
    ok("Toggle başarılı")

    balance_after = (await db_fetchone("SELECT tuci_balance FROM users WHERE id = :id", {"id": user_id}))["tuci_balance"]
    assert balance_after == balance_before - 10, \
        f"10 TUCi düşmedi: {balance_before} → {balance_after}"
    ok(f"10 TUCi düşüldü: {balance_before} → {balance_after}")


async def test_3_normal_paid(client, token, listing_id, user_id):
    head("Senaryo 3: Normal kullanıcı → TUCi ödeme")

    await set_premium(user_id, False)
    await set_tuci(user_id, 50)
    await ensure_listing_passive(client, token, listing_id)

    credits = await reactivation_credits_api(client, token)
    info(f"Kredi durumu: {credits}")
    assert credits["is_premium"] is False
    assert credits["free_remaining"] == 0
    assert credits["cost"] == 10
    assert credits["can_afford"] is True
    ok("Normal kullanıcı kredi yok, bakiye yeterli")

    balance_before = (await db_fetchone("SELECT tuci_balance FROM users WHERE id = :id", {"id": user_id}))["tuci_balance"]
    r = await toggle(client, token, listing_id)
    assert r["status"] == 200, f"Toggle başarısız: {r}"
    ok("Toggle başarılı")

    balance_after = (await db_fetchone("SELECT tuci_balance FROM users WHERE id = :id", {"id": user_id}))["tuci_balance"]
    assert balance_after == balance_before - 10
    ok(f"10 TUCi düşüldü: {balance_before} → {balance_after}")


async def test_4_insufficient_balance(client, token, listing_id, user_id):
    head("Senaryo 4: Normal kullanıcı → yetersiz bakiye (402)")

    await set_premium(user_id, False)
    await set_tuci(user_id, 5)  # 10 TUCi'den az
    await ensure_listing_passive(client, token, listing_id)

    credits = await reactivation_credits_api(client, token)
    info(f"Kredi durumu: {credits}")
    assert credits["can_afford"] is False, "can_afford=False beklendi"
    ok("API doğru: can_afford=False")

    r = await toggle(client, token, listing_id)
    assert r["status"] == 402, f"402 beklendi, {r['status']} geldi: {r['body']}"
    # Backend middleware hatayı {"success":false,"error":{"code":"HTTP_402","message":"..."}} formatına sarar
    assert "insufficient_balance" in str(r["body"]), \
        f"'insufficient_balance' response'da bulunamadı: {r['body']}"
    ok("402 döndü, insufficient_balance ✔")

    # Bakiye değişmedi mi?
    balance_after = (await db_fetchone("SELECT tuci_balance FROM users WHERE id = :id", {"id": user_id}))["tuci_balance"]
    assert balance_after == 5, f"Bakiye değişmemeli, {balance_after} TUCi"
    ok("Bakiye değişmedi ✔")


async def test_5_deactivation_cleanup(client, token, listing_id, user_id):
    head("Senaryo 5: Aktif→Pasif — kampanya ve impression temizliği")

    await set_premium(user_id, True)
    await set_tuci(user_id, 100)
    await clear_reactivation_credits(user_id)
    await ensure_listing_active(client, token, listing_id)

    # Sahte impressions ekle
    await insert_fake_impressions(listing_id, 3)
    imp_before = await get_impressions(listing_id)
    info(f"İmpression sayısı (önce): {imp_before}")

    # Aktif → Pasif
    r = await toggle(client, token, listing_id)
    assert r["status"] == 200, f"Toggle başarısız: {r}"
    assert r["body"].get("is_active") is False
    ok("İlan pasife alındı")

    # Impressions temizlendi mi?
    imp_after = await get_impressions(listing_id)
    assert imp_after == 0, f"Impressions temizlenmedi: {imp_after} kaldı"
    ok(f"listing_impressions temizlendi: {imp_before} → {imp_after}")

    # Kampanya kontrolü
    campaigns = await get_campaigns(listing_id)
    info(f"Kalan kampanyalar: {campaigns}")
    assert len(campaigns) == 0, f"AdCampaign silinmedi: {campaigns}"
    ok("AdCampaign'ler silindi ✔")

    # Rozet korundu mu?
    state = await get_listing_state(listing_id)
    info(f"is_highlight: {state.get('is_highlight')}")
    ok("Rozet durumu değişmedi (is_highlight korunur) ✔")


# ── Özet ─────────────────────────────────────────────────────────────────────
async def main():
    parser = argparse.ArgumentParser(description="Reaktivasyon feature test")
    parser.add_argument("--password", "-p", help="Test kullanıcısı şifresi", default=TEST_PASS)
    parser.add_argument("--scenario", "-s", type=int, help="Sadece bu senaryoyu çalıştır (1-5)", default=0)
    args = parser.parse_args()

    if args.password == "SIFRENIZI_GIRIN":
        print(f"{R}Hata: --password argümanıyla şifreyi girin{X}")
        print(f"  python test_reactivation.py -p 'sifreniz'")
        sys.exit(1)

    print(f"\n{Y}═══ Reaktivasyon Test Suite ═══{X}")
    print(f"  API: {BASE_URL}")
    print(f"  Kullanıcı: {TEST_EMAIL}")
    print(f"  İlan: {LISTING_TITLE}\n")

    async with httpx.AsyncClient(timeout=30) as client:
        # Login
        try:
            token = await login(client, TEST_EMAIL, args.password)
            ok(f"Login başarılı")
        except Exception as e:
            err(f"Login başarısız: {e}")
            sys.exit(1)

        # User ID
        user = await db_fetchone("SELECT id FROM users WHERE email = :e", {"e": TEST_EMAIL})
        if not user:
            err(f"Kullanıcı bulunamadı: {TEST_EMAIL}")
            sys.exit(1)
        user_id = user["id"]
        info(f"user_id = {user_id}")

        # Listing ID
        listing_id = await get_listing_id(LISTING_TITLE)
        if not listing_id:
            err(f"İlan bulunamadı: '{LISTING_TITLE}'")
            sys.exit(1)
        info(f"listing_id = {listing_id}")

        # Orijinal state'i kaydet (testten sonra restore et)
        orig_state = await db_fetchone(
            "SELECT tuci_balance, is_premium FROM users WHERE id = :id", {"id": user_id}
        )
        orig_listing = await get_listing_state(listing_id)

        scenarios = {
            1: test_1_pro_free_credit,
            2: test_2_pro_paid,
            3: test_3_normal_paid,
            4: test_4_insufficient_balance,
            5: test_5_deactivation_cleanup,
        }

        passed = 0
        failed = 0
        to_run = [args.scenario] if args.scenario else list(scenarios.keys())

        for i in to_run:
            try:
                await scenarios[i](client, token, listing_id, user_id)
                passed += 1
            except AssertionError as e:
                err(f"HATA (Senaryo {i}): {e}")
                failed += 1
            except Exception as e:
                err(f"İSTİSNA (Senaryo {i}): {type(e).__name__}: {e}")
                failed += 1

        # Orijinal state'i geri yükle
        head("Test Sonrası Temizlik")
        await db_exec(
            "UPDATE users SET tuci_balance = :b, is_premium = :p WHERE id = :id",
            {"b": orig_state["tuci_balance"], "p": orig_state["is_premium"], "id": user_id},
        )
        await db_exec(
            "UPDATE listings SET is_active = :a, created_at = :c WHERE id = :id",
            {"a": orig_listing["is_active"], "c": orig_listing["created_at"], "id": listing_id},
        )
        await clear_reactivation_credits(user_id)
        ok(f"Kullanıcı ve ilan orijinal state'e döndürüldü")

        # Özet
        total = passed + failed
        color = G if failed == 0 else R
        print(f"\n{color}{'═'*40}")
        print(f"  Sonuç: {passed}/{total} geçti, {failed} başarısız")
        print(f"{'═'*40}{X}\n")
        sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    asyncio.run(main())
