"""
Privacy & Block Sistem Test Scripti
====================================
Kullanım:
  python3 scripts/test_privacy_block.py

Gereksinimler:
  pip install requests psycopg2-binary redis python-dotenv

DB ve Redis bağlantıları backend/.env dosyasından otomatik okunur.
"""

import os
import sys
import time
import getpass
import requests
import psycopg2
import redis as redis_lib
from dotenv import load_dotenv

# backend/.env'i yükle
_script_dir = os.path.dirname(os.path.abspath(__file__))
_backend_dir = os.path.dirname(_script_dir)
load_dotenv(os.path.join(_backend_dir, ".env"))

def _db_url_from_env():
    url = os.environ.get("DATABASE_URL", "")
    # SQLAlchemy async driver prefix'ini psycopg2 için düşür
    return url.replace("postgresql+asyncpg://", "postgresql://")

def _redis_url_from_env():
    return os.environ.get("REDIS_URL", "redis://localhost:6379")

# ── Renk yardımcıları ─────────────────────────────────────────────────────────

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def ok(msg):     print(f"  {GREEN}✓ {msg}{RESET}")
def fail(msg):   print(f"  {RED}✗ {msg}{RESET}")
def info(msg):   print(f"  {YELLOW}· {msg}{RESET}")
def header(msg): print(f"\n{'='*60}\n  {msg}\n{'='*60}")
def section(msg):print(f"\n── {msg} ──")

def ask(prompt, default=None, secret=False):
    label = f"{CYAN}{prompt}"
    if default:
        label += f" [{default}]"
    label += f"{RESET}: "
    val = getpass.getpass(label) if secret else input(label)
    return val.strip() or (default or "")

# ── Sonuç sayacı ──────────────────────────────────────────────────────────────

_passed = 0
_failed = 0

def check(condition, pass_msg, fail_msg):
    global _passed, _failed
    if condition:
        ok(pass_msg)
        _passed += 1
    else:
        fail(fail_msg)
        _failed += 1

# ── Yapılandırma toplama ──────────────────────────────────────────────────────

def collect_config():
    print(f"\n{CYAN}{'─'*60}")
    print("  Teqlif Privacy & Block — Test Yapılandırması")
    print(f"{'─'*60}{RESET}\n")

    base_url = ask("API base URL", default="https://www.teqlif.com/api")

    print(f"\n{CYAN}Kullanıcı A — Gizli hesap (is_private=true){RESET}")
    user_a = ask("  Kullanıcı adı")
    pass_a = ask("  Şifre", secret=True)

    print(f"\n{CYAN}Kullanıcı B — A'yı takip etmeyen kullanıcı{RESET}")
    user_b = ask("  Kullanıcı adı")
    pass_b = ask("  Şifre", secret=True)

    print(f"\n{CYAN}Kullanıcı C — A'nın onaylı takipçisi{RESET}")
    user_c = ask("  Kullanıcı adı")
    pass_c = ask("  Şifre", secret=True)

    db_url    = _db_url_from_env()
    redis_url = _redis_url_from_env()

    print()
    return base_url, user_a, pass_a, user_b, pass_b, user_c, pass_c, db_url, redis_url

def login(base_url, username, password):
    resp = requests.post(f"{base_url}/auth/login", json={
        "login_identifier": username,
        "password": password,
    })
    if resp.status_code != 200:
        print(f"{RED}Giriş başarısız [{username}]: {resp.text}{RESET}")
        sys.exit(1)
    data = resp.json()
    token = data["access_token"]
    user_id = data.get("user", {}).get("id") or _fetch_me_id(base_url, token)
    return token, user_id

def _fetch_me_id(base_url, token):
    r = requests.get(f"{base_url}/auth/me", headers=_h(token))
    return r.json().get("id")

def _h(token):
    return {"Authorization": f"Bearer {token}", "Accept-Language": "tr"}

# ── DB & Redis bağlantısı ────────────────────────────────────────────────────

def db_conn(db_url):
    if not db_url:
        info("DB bağlantısı girilmedi — DB kontrolleri atlanacak")
        return None
    try:
        return psycopg2.connect(db_url)
    except Exception as e:
        info(f"DB bağlantısı kurulamadı: {e}")
        return None

def redis_conn(redis_url):
    if not redis_url:
        return None
    try:
        r = redis_lib.from_url(redis_url)
        r.ping()
        return r
    except Exception as e:
        info(f"Redis bağlantısı kurulamadı: {e}")
        return None

def db_query(conn, sql, params=()):
    if not conn:
        return None
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        return cur.fetchall()
    except Exception as e:
        info(f"DB sorgu hatası: {e}")
        return None

# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def set_private(base_url, token, is_private):
    r = requests.patch(f"{base_url}/auth/me", headers=_h(token),
                       json={"is_private": is_private})
    assert r.status_code == 200, f"is_private değiştirilemedi: {r.text}"

def send_message(base_url, token, receiver_id, text="Merhaba, test mesajı."):
    r = requests.post(f"{base_url}/messages/send", headers=_h(token),
                      json={"receiver_id": receiver_id, "content": text})
    return r

def get_thread_status(base_url, token, other_id):
    r = requests.get(f"{base_url}/messages/thread/{other_id}/status", headers=_h(token))
    return r.json() if r.status_code == 200 else {}

def get_message_requests(base_url, token):
    r = requests.get(f"{base_url}/messages/requests", headers=_h(token))
    return r.json() if r.status_code == 200 else []

def get_conversations(base_url, token):
    r = requests.get(f"{base_url}/messages/conversations", headers=_h(token))
    return r.json() if r.status_code == 200 else []

def accept_request(base_url, token, requester_id):
    r = requests.post(f"{base_url}/messages/requests/{requester_id}/accept",
                      headers=_h(token))
    return r

def decline_request(base_url, token, requester_id):
    r = requests.post(f"{base_url}/messages/requests/{requester_id}/decline",
                      headers=_h(token))
    return r

def get_profile(base_url, token, username):
    r = requests.get(f"{base_url}/users/{username}", headers=_h(token))
    return r.json() if r.status_code == 200 else {}

def get_follower_list(base_url, token, user_id):
    r = requests.get(f"{base_url}/follows/{user_id}/followers", headers=_h(token))
    return r.status_code, r.json()

def accept_follow_request(base_url, token, follower_id):
    r = requests.post(f"{base_url}/follows/{follower_id}/accept", headers=_h(token))
    return r.status_code

# ── TEST BLOKLARI ─────────────────────────────────────────────────────────────

def test_profil_gating(base_url, token_b, token_c, username_a, db):
    header("BÖLÜM 2 — Profil Gizliliği (Task 2)")

    section("B (takipçi değil) → A gizli profilini görüyor")
    profile = get_profile(base_url, token_b, username_a)
    check("bio" not in profile or profile.get("bio") is None,
          "bio gizli", "bio görünüyor — hata!")
    check("follower_count" not in profile or profile.get("follower_count") is None,
          "follower_count gizli", "follower_count görünüyor — hata!")
    check("full_name" not in profile or profile.get("full_name") is None,
          "full_name gizli", "full_name görünüyor — hata!")
    check(profile.get("username") is not None,
          "username görünüyor", "username gizlenmiş — hata!")

    section("C (onaylı takipçi) → A profilini tam görüyor")
    profile_c = get_profile(base_url, token_c, username_a)
    check(profile_c.get("follower_count") is not None,
          "follower_count görünüyor", "follower_count gizli — hata!")


def test_follower_list_gating(base_url, token_b, token_c, user_a_id):
    header("BÖLÜM 3 — Follower/Following Liste Gizliliği (Task 3)")

    section("B (takipçi değil) → A'nın follower listesi 403 bekleniyor")
    status, _ = get_follower_list(base_url, token_b, user_a_id)
    check(status == 403, f"403 döndü ({status})", f"403 beklendi, {status} geldi")

    section("C (onaylı takipçi) → A'nın follower listesi 200 bekleniyor")
    status, _ = get_follower_list(base_url, token_c, user_a_id)
    check(status == 200, f"200 döndü ({status})", f"200 beklendi, {status} geldi")


def test_message_requests(base_url, token_a, token_b, user_a_id, user_b_id, db, rdb):
    header("BÖLÜM 5 — Mesaj İstekleri (Task 5)")

    # Önceki thread temizleme (mümkünse)
    if db:
        a, b = min(user_a_id, user_b_id), max(user_a_id, user_b_id)
        try:
            cur = db.cursor()
            cur.execute("DELETE FROM message_threads WHERE user_a_id=%s AND user_b_id=%s", (a, b))
            db.commit()
            info("Önceki thread temizlendi")
        except Exception as e:
            info(f"Thread temizlenemedi: {e}")

    section("S5.1 — B → A'ya mesaj gönder (pending bekleniyor)")
    r = send_message(base_url, token_b, user_a_id)
    check(r.status_code in [200, 201],
          f"Mesaj gönderildi ({r.status_code})",
          f"Mesaj gönderilemedi: {r.text}")

    time.sleep(0.5)

    section("S5.2 — Thread durumu kontrolü")
    status_b = get_thread_status(base_url, token_b, user_a_id)
    check(status_b.get("status") == "pending",
          "B açısından status=pending ✓", f"B açısından status={status_b.get('status')} (pending bekleniyor)")
    check(status_b.get("is_initiator") is True,
          "B is_initiator=True ✓", f"B is_initiator={status_b.get('is_initiator')} (True bekleniyor)")

    status_a = get_thread_status(base_url, token_a, user_b_id)
    check(status_a.get("status") == "pending",
          "A açısından status=pending ✓", f"A açısından status={status_a.get('status')}")
    check(status_a.get("is_initiator") is False,
          "A is_initiator=False ✓", f"A is_initiator={status_a.get('is_initiator')} (False bekleniyor)")

    section("S5.3 — A'nın istek listesinde B var mı?")
    requests_list = get_message_requests(base_url, token_a)
    requester_ids = [r.get("user_id") for r in requests_list]
    check(user_b_id in requester_ids,
          "B İstekler listesinde ✓", "B İstekler listesinde bulunamadı — hata!")

    section("S5.4 — Initiator (B) Konuşmalar listesinde görünüyor mu?")
    convs_b = get_conversations(base_url, token_b)
    conv_ids_b = [c.get("user_id") for c in convs_b]
    check(user_a_id in conv_ids_b,
          "B'nin Konuşmalar listesinde A var ✓", "B'nin Konuşmalar listesinde A yok — hata!")

    section("S5.5 — A'nın Konuşmalar listesine B sızmamış")
    convs_a = get_conversations(base_url, token_a)
    conv_ids_a = [c.get("user_id") for c in convs_a]
    check(user_b_id not in conv_ids_a,
          "A'nın Konuşmalar listesinde B yok ✓", "A'nın Konuşmalar listesine B sızmış — hata!")

    section("S5.6 — DB: message_threads durumu")
    if db:
        a, b = min(user_a_id, user_b_id), max(user_a_id, user_b_id)
        rows = db_query(db,
            "SELECT status, initiator_id FROM message_threads WHERE user_a_id=%s AND user_b_id=%s",
            (a, b))
        if rows:
            st, init = rows[0]
            check(st == "pending", f"DB status=pending ✓", f"DB status={st}")
            check(init == user_b_id, f"DB initiator_id={user_b_id} ✓", f"DB initiator_id={init}")
        else:
            fail("DB'de thread bulunamadı")
    else:
        info("DB kontrolü atlandı (DB bağlantısı yok)")

    section("S5.7 — Redis: request count > 0")
    if rdb:
        count = rdb.get(f"msg:unread:request:{user_a_id}")
        count_val = int(count) if count else 0
        check(count_val > 0, f"Redis request count={count_val} ✓",
              f"Redis request count={count_val} (>0 bekleniyor)")
    else:
        info("Redis kontrolü atlandı (Redis bağlantısı yok)")

    section("S5.8 — Manuel kabul: A, B'yi kabul ediyor")
    r = accept_request(base_url, token_a, user_b_id)
    check(r.status_code == 200,
          f"Accept 200 ✓", f"Accept {r.status_code}: {r.text}")

    time.sleep(0.3)

    status_after = get_thread_status(base_url, token_a, user_b_id)
    check(status_after.get("status") == "accepted",
          "Kabul sonrası status=accepted ✓",
          f"Kabul sonrası status={status_after.get('status')}")

    if rdb:
        count_after = rdb.get(f"msg:unread:request:{user_a_id}")
        count_after_val = int(count_after) if count_after else 0
        check(count_after_val == 0,
              "Kabul sonrası Redis count=0 ✓",
              f"Kabul sonrası Redis count={count_after_val} (0 bekleniyor)")


def test_decline(base_url, token_a, token_b, user_a_id, user_b_id, db, rdb):
    header("S5 EK — Soft Decline Testi")

    # Yeni pending thread oluştur
    if db:
        a, b = min(user_a_id, user_b_id), max(user_a_id, user_b_id)
        try:
            cur = db.cursor()
            cur.execute("DELETE FROM message_threads WHERE user_a_id=%s AND user_b_id=%s", (a, b))
            db.commit()
        except Exception:
            pass

    send_message(base_url, token_b, user_a_id, "Decline testi için mesaj")
    time.sleep(0.5)

    section("A, B'yi reddediyor")
    r = decline_request(base_url, token_a, user_b_id)
    check(r.status_code == 200,
          f"Decline 200 ✓", f"Decline {r.status_code}: {r.text}")

    time.sleep(0.3)

    section("Thread durumu declined olmuş mu?")
    status = get_thread_status(base_url, token_a, user_b_id)
    check(status.get("status") == "declined",
          "status=declined ✓",
          f"status={status.get('status')} (declined bekleniyor)")

    section("B'nin Konuşmalar listesinde A hâlâ var mı? (B habersiz)")
    convs_b = get_conversations(base_url, token_b)
    conv_ids_b = [c.get("user_id") for c in convs_b]
    check(user_a_id in conv_ids_b,
          "B'nin listesinde A var (soft decline — B habersiz) ✓",
          "B'nin listesinden A kaybolmuş — hata! (B haberdar olmamalı)")


def test_open_account_no_pending(base_url, token_a, token_b, user_a_id, user_b_id, db):
    header("BÖLÜM 8 — Regresyon: Açık Hesaba Mesaj → Pending Olmamalı")

    # A'yı açık yap
    set_private(base_url, token_a, False)
    time.sleep(0.3)

    # Önceki thread sil
    if db:
        a, b = min(user_a_id, user_b_id), max(user_a_id, user_b_id)
        try:
            cur = db.cursor()
            cur.execute("DELETE FROM message_threads WHERE user_a_id=%s AND user_b_id=%s", (a, b))
            db.commit()
        except Exception:
            pass

    send_message(base_url, token_b, user_a_id, "Açık hesap regresyon testi")
    time.sleep(0.5)

    status = get_thread_status(base_url, token_b, user_a_id)
    check(status.get("status") == "accepted",
          "Açık hesapta status=accepted ✓",
          f"Açık hesapta status={status.get('status')} (accepted bekleniyor — pending olmamalı)")

    # A'yı tekrar gizli yap
    set_private(base_url, token_a, True)


def test_privacy_kapatma_bulk_promote(base_url, token_a, user_a_id, db, rdb):
    header("M5.8 — Gizlilik Kapatınca Toplu Promosyon")

    if not db:
        info("DB bağlantısı yok — bu test atlanıyor")
        return

    a_id = user_a_id
    rows = db_query(db,
        "SELECT COUNT(*) FROM message_threads WHERE (user_a_id=%s OR user_b_id=%s) AND status='pending'",
        (a_id, a_id))
    pending_before = rows[0][0] if rows else 0
    info(f"Gizlilik kapatmadan önce pending thread sayısı: {pending_before}")

    set_private(base_url, token_a, False)
    time.sleep(1)

    rows_after = db_query(db,
        "SELECT COUNT(*) FROM message_threads WHERE (user_a_id=%s OR user_b_id=%s) AND status='pending'",
        (a_id, a_id))
    pending_after = rows_after[0][0] if rows_after else -1

    check(pending_after == 0,
          "Gizlilik açıldı → tüm pending thread accepted'a döndü ✓",
          f"Hâlâ {pending_after} pending thread var — hata!")

    if rdb:
        count = rdb.get(f"msg:unread:request:{a_id}")
        check(count is None or int(count) == 0,
              "Redis request count temizlendi ✓",
              f"Redis request count hâlâ {count}")

    set_private(base_url, token_a, True)


# ── ANA ÇALIŞMA ───────────────────────────────────────────────────────────────

def main():
    base_url, user_a, pass_a, user_b, pass_b, user_c, pass_c, db_url, redis_url = collect_config()

    print(f"\n{'='*60}")
    print("  Teqlif Privacy & Block — Otomatik Test Scripti")
    print(f"  Hedef : {base_url}")
    print(f"  DB    : {'✓ .env'if db_url else '✗ bulunamadı'}")
    print(f"  Redis : {'✓ .env' if redis_url else '✗ bulunamadı'}")
    print(f"{'='*60}")

    print("\n[Giriş yapılıyor...]")
    token_a, user_a_id = login(base_url, user_a, pass_a)
    token_b, user_b_id = login(base_url, user_b, pass_b)
    token_c, user_c_id = login(base_url, user_c, pass_c)
    info(f"A id={user_a_id}  B id={user_b_id}  C id={user_c_id}")

    # A'yı gizli yap (tüm testler için ön koşul)
    set_private(base_url, token_a, True)
    info("A hesabı gizli olarak ayarlandı")

    db  = db_conn(db_url)
    rdb = redis_conn(redis_url)

    # Testleri çalıştır
    test_profil_gating(base_url, token_b, token_c, user_a, db)
    test_follower_list_gating(base_url, token_b, token_c, user_a_id)
    test_message_requests(base_url, token_a, token_b, user_a_id, user_b_id, db, rdb)
    test_decline(base_url, token_a, token_b, user_a_id, user_b_id, db, rdb)
    test_open_account_no_pending(base_url, token_a, token_b, user_a_id, user_b_id, db)
    test_privacy_kapatma_bulk_promote(base_url, token_a, user_a_id, db, rdb)

    # Özet
    total = _passed + _failed
    print(f"\n{'='*60}")
    print(f"  Sonuç: {GREEN}{_passed} geçti{RESET} / {RED}{_failed} başarısız{RESET} / {total} toplam")
    print(f"{'='*60}\n")

    if db:
        db.close()

    sys.exit(0 if _failed == 0 else 1)


if __name__ == "__main__":
    main()
