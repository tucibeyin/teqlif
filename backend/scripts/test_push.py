#!/usr/bin/env python3
"""
FCM Push Notification Diagnostik Script
Çalıştırma: python test_push.py [gönderen] [alıcı]
Örnek:      python test_push.py 2gbrain tucibeyin
"""

import asyncio
import sys
import os
import time
import subprocess

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

GRN = "\033[92m"; RED = "\033[91m"; YLW = "\033[93m"
BLU = "\033[94m"; MAG = "\033[95m"; CYN = "\033[96m"
RST = "\033[0m";  BLD = "\033[1m"

def ok(msg):   print(f"  {GRN}✓{RST} {msg}")
def err(msg):  print(f"  {RED}✗{RST} {msg}")
def warn(msg): print(f"  {YLW}!{RST} {msg}")
def info(msg): print(f"  {BLU}→{RST} {msg}")
def hdr(msg):  print(f"\n{BLD}{CYN}{'─'*60}{RST}\n{BLD}{CYN}  {msg}{RST}\n{BLD}{CYN}{'─'*60}{RST}")
def sh(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.stdout.strip()


async def main():
    sender_username   = sys.argv[1] if len(sys.argv) > 1 else "2gbrain"
    receiver_username = sys.argv[2] if len(sys.argv) > 2 else "tucibeyin"

    print(f"\n{BLD}FCM Push Diagnostik{RST} — {MAG}{sender_username}{RST} → {MAG}{receiver_username}{RST}\n")

    # ── 0. Backend Versiyon ───────────────────────────────────────────────────
    hdr("0. Backend Versiyon ve Servis Durumu")

    git_hash = sh("git -C /var/www/teqlif.com rev-parse --short HEAD")
    info(f"Git commit   : {git_hash}")

    svc_since = sh("systemctl show teqlif --property=ActiveEnterTimestamp --value")
    info(f"teqlif since : {svc_since}")

    # Fix commit hash
    fix_hash = sh("git -C /var/www/teqlif.com log --oneline | grep 'fcm-token endpoint' | head -1")
    if fix_hash:
        ok(f"Fix commit   : {fix_hash[:60]}")
    else:
        warn("Fix commit bulunamadı — 'fcm-token endpoint' commit eksik olabilir")

    # ── 1. ENV + DB ───────────────────────────────────────────────────────────
    hdr("1. Veritabanı — Kullanıcı ve FCM Token Bilgileri")

    os.environ.setdefault("ENVIRONMENT", "production")
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

    from app.database import AsyncSessionLocal
    from app.models.user import User
    from sqlalchemy import select, update as sa_update, text

    async with AsyncSessionLocal() as db:
        sender   = (await db.execute(select(User).where(User.username == sender_username))).scalar_one_or_none()
        receiver = (await db.execute(select(User).where(User.username == receiver_username))).scalar_one_or_none()

    if not sender:
        err(f"'{sender_username}' DB'de bulunamadı"); return
    if not receiver:
        err(f"'{receiver_username}' DB'de bulunamadı"); return

    ok(f"Gönderen  : {sender.username} (id={sender.id})")
    ok(f"Alıcı     : {receiver.username} (id={receiver.id})")
    (ok if receiver.fcm_token else err)(
        f"FCM token : {receiver.fcm_token[:40]}…" if receiver.fcm_token else
        f"FCM token YOK (NULL)"
    )

    # Nginx'ten son 5 fcm-token isteğini göster
    info("Son fcm-token istekleri (nginx):")
    lines = sh("grep 'fcm-token' /var/log/nginx/access.log | tail -5")
    for l in lines.splitlines():
        print(f"    {l}")

    # ── 1b. DB Yazma Testi ────────────────────────────────────────────────────
    hdr("1b. DB Yazma Testi — token doğrudan DB'ye kaydediliyor mu?")

    test_token = f"TEST_TOKEN_{int(time.time())}"
    async with AsyncSessionLocal() as db:
        await db.execute(sa_update(User).where(User.id == receiver.id).values(fcm_token=test_token))
        await db.commit()

    # Yeni session'da oku — gerçekten yazıldı mı?
    async with AsyncSessionLocal() as db:
        row = (await db.execute(select(User.fcm_token).where(User.id == receiver.id))).scalar_one()

    if row == test_token:
        ok(f"DB yazma çalışıyor (test token kaydedildi)")
    else:
        err(f"DB yazma BOZUK! Yazılan: {test_token[:20]}, Okunan: {str(row)[:20]}")
        await (await __import__('app.utils.redis_client', fromlist=['get_redis']).get_redis()).aclose()
        return

    # Test token'ı temizle — gerçek token bekliyoruz
    async with AsyncSessionLocal() as db:
        await db.execute(sa_update(User).where(User.id == receiver.id).values(fcm_token=None))
        await db.commit()
    info("Test token temizlendi, alıcının gerçek token kaydı için uygulamayı aç/kapat")

    # ── 1c. API Endpoint Kodu Doğrulaması ────────────────────────────────────
    hdr("1c. /auth/fcm-token Endpoint Kodu — fix yüklü mü?")

    endpoint_file = "/var/www/teqlif.com/backend/app/routers/auth.py"
    endpoint_src = sh(f"grep -A 15 'def save_fcm_token' {endpoint_file}")
    if "sa_update" in endpoint_src or "sa_update(User)" in endpoint_src:
        ok("Fix yüklü — endpoint direkt UPDATE kullanıyor")
    elif "current_user.fcm_token = token" in endpoint_src:
        err("ESKİ KOD ÇALIŞIYOR — ORM assignment ile (token kaydedilmiyor)")
        err("Servisi yeniden başlat: sudo systemctl restart teqlif")
        info("Endpoint kodu:")
        for l in endpoint_src.splitlines()[:10]:
            print(f"    {l}")
    else:
        info("Endpoint kodu:")
        for l in endpoint_src.splitlines()[:10]:
            print(f"    {l}")

    # ── 2. Circuit Breaker ────────────────────────────────────────────────────
    hdr("2. Redis Circuit Breaker")

    from app.utils.redis_client import get_redis
    redis = await get_redis()
    cb_state    = (await redis.get("cb:fcm:state"))    or "closed"
    cb_failures = (await redis.get("cb:fcm:failures")) or "0"
    (ok if cb_state != "open" else err)(f"Circuit breaker: {cb_state} (failures={cb_failures})")

    # FCM token tekrar oku
    async with AsyncSessionLocal() as db:
        receiver = (await db.execute(select(User).where(User.id == receiver.id))).scalar_one()

    if not receiver.fcm_token:
        warn("FCM token hâlâ NULL — uygulamayı aç/kapat, sonra tekrar çalıştır")
        info("Servisin yeni kodu yükleyip yüklemediğini kontrol et: sudo systemctl status teqlif")
        await redis.aclose()
        return

    ok(f"FCM token alındı: {receiver.fcm_token[:35]}…")

    # ── 3. ARQ Pool ───────────────────────────────────────────────────────────
    hdr("3. ARQ Pool Başlatma")

    from arq import create_pool
    from arq.connections import RedisSettings
    from app.config import settings as app_settings
    from app.core.task_queue import set_pool

    arq_pool = await create_pool(RedisSettings.from_dsn(app_settings.redis_url))
    set_pool(arq_pool)
    ok(f"ARQ pool başlatıldı → {app_settings.redis_url[:30]}…")

    # ── 4a. ARQ — doğrudan enqueue ────────────────────────────────────────────
    hdr("4a. ARQ — doğrudan send_push_notification_task")

    q0 = await redis.llen("arq:queue:default")
    job = await arq_pool.enqueue_job(
        "send_push_notification_task",
        receiver.fcm_token,
        f"[4a ARQ Test] {sender_username}",
        "ARQ doğrudan enqueue testi",
        None, "message",
        {"sender_username": sender_username},
        None,
    )
    await asyncio.sleep(0.5)
    q1 = await redis.llen("arq:queue:default")
    ok(f"job_id={getattr(job, 'job_id', '?')} | kuyruk: {q0}→{q1}")

    # ── 4b. push_notification() pipeline ─────────────────────────────────────
    hdr("4b. push_notification() — tam pipeline")

    from app.routers.notifications import push_notification
    from app.schemas.user import DEFAULT_NOTIF_PREFS

    async with AsyncSessionLocal() as db:
        u = await db.get(User, receiver.id)
        prefs = u.notification_prefs or {}
        merged = {**DEFAULT_NOTIF_PREFS, **prefs}
    info(f"messages: {merged.get('messages')}  quiet_hours: {merged.get('quiet_hours_enabled')}")

    q2 = await redis.llen("arq:queue:default")
    try:
        await push_notification(
            receiver.id,
            {"type": "message", "body": f"[4b Test] {sender_username}", "sender_username": sender_username},
            pref_key="messages",
        )
        ok("push_notification() tamamlandı")
    except Exception as exc:
        err(f"push_notification() HATA: {exc}")

    samples = [await redis.llen("arq:queue:default") for _ in range(5) if not await asyncio.sleep(0.2)]  # type: ignore[func-returns-value]
    peak = max(samples)
    (ok if peak > q2 else warn)(f"ARQ kuyruk: önce={q2} samples={samples} peak={peak}")

    # ── 5. Doğrudan Firebase ─────────────────────────────────────────────────
    hdr("5. send_push() — Doğrudan Firebase")

    from app.services.firebase_service import send_push, InvalidFCMTokenError

    t = time.monotonic()
    try:
        await send_push(
            token=receiver.fcm_token,
            title=f"🔔 Diagnostik ({sender_username})",
            body="Test bildirimi — doğrudan Firebase",
            notif_type="message",
            extra_data={"sender_username": sender_username},
        )
        elapsed = (time.monotonic() - t) * 1000
        ok(f"Firebase kabul etti ({elapsed:.0f}ms)")
        print(f"\n  {BLD}>>> Bu bildirim telefona GELDİ mi? <<<{RST}")
        print(f"  {GRN}Evet{RST}: iOS/APNs çalışıyor, sorun ARQ pipeline'da")
        print(f"  {RED}Hayır{RST}: iOS bildirim izni veya APNs ortam sorunu\n")
    except InvalidFCMTokenError:
        err("FCM TOKEN GEÇERSİZ — yeni token kaydedilmeli (uygulamayı aç)")
    except Exception as exc:
        err(f"Firebase HATA: {type(exc).__name__}: {exc}")

    # ── 6. Worker Log ─────────────────────────────────────────────────────────
    hdr("6. Son Worker Logları")

    worker_log = sh("journalctl -u teqlif-worker --no-pager -n 20")
    fcm_lines = [l for l in worker_log.splitlines() if any(k in l for k in ["[FCM]", "[Worker]", "Error", "error", "push"])]
    if fcm_lines:
        for l in fcm_lines[-10:]:
            print(f"  {l}")
    else:
        warn("Worker'da ilgili log bulunamadı")
        info("Canlı izle: sudo journalctl -u teqlif-worker -f")

    # ── Özet ──────────────────────────────────────────────────────────────────
    hdr("ÖZET")
    ok(f"FCM token  : mevcut") if receiver.fcm_token else err("FCM token  : YOK")
    (ok if cb_state != "open" else err)(f"CB         : {cb_state}")
    print()
    info("Servis yeniden başlatma: sudo systemctl restart teqlif")
    print()

    await arq_pool.aclose()
    await redis.aclose()


if __name__ == "__main__":
    asyncio.run(main())
