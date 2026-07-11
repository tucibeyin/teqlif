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

# backend/ dizinini path'e ekle (scripts/ içinden çalıştırılınca app modülü bulunabilsin)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# ── Renk kodları ──────────────────────────────────────────────────────────────
GRN = "\033[92m"; RED = "\033[91m"; YLW = "\033[93m"
BLU = "\033[94m"; MAG = "\033[95m"; CYN = "\033[96m"
RST = "\033[0m";  BLD = "\033[1m"

def ok(msg):   print(f"  {GRN}✓{RST} {msg}")
def err(msg):  print(f"  {RED}✗{RST} {msg}")
def warn(msg): print(f"  {YLW}!{RST} {msg}")
def info(msg): print(f"  {BLU}→{RST} {msg}")
def hdr(msg):  print(f"\n{BLD}{CYN}{'─'*60}{RST}\n{BLD}{CYN}  {msg}{RST}\n{BLD}{CYN}{'─'*60}{RST}")


async def main():
    sender_username   = sys.argv[1] if len(sys.argv) > 1 else "2gbrain"
    receiver_username = sys.argv[2] if len(sys.argv) > 2 else "tucibeyin"

    print(f"\n{BLD}FCM Push Diagnostik{RST} — {MAG}{sender_username}{RST} → {MAG}{receiver_username}{RST}\n")

    # ── 1. ENV + DB ───────────────────────────────────────────────────────────
    hdr("1. Veritabanı — Kullanıcı ve FCM Token Bilgileri")

    os.environ.setdefault("ENVIRONMENT", "production")
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

    from app.database import AsyncSessionLocal
    from app.models.user import User
    from sqlalchemy import select

    async with AsyncSessionLocal() as db:
        sender   = (await db.execute(select(User).where(User.username == sender_username))).scalar_one_or_none()
        receiver = (await db.execute(select(User).where(User.username == receiver_username))).scalar_one_or_none()

    if not sender:
        err(f"'{sender_username}' DB'de bulunamadı"); return
    if not receiver:
        err(f"'{receiver_username}' DB'de bulunamadı"); return

    ok(f"Gönderen  : {sender.username} (id={sender.id})")
    ok(f"Alıcı     : {receiver.username} (id={receiver.id})")

    if receiver.fcm_token:
        ok(f"FCM token : {receiver.fcm_token[:40]}…")
    else:
        err(f"FCM token YOK — '{receiver_username}' için DB'de fcm_token = NULL")
        err("Alıcı uygulamayı açsın → splash screen token'ı otomatik kaydeder")
        info("Kontrol: sudo journalctl -u teqlif --no-pager | grep fcm-token")

    # ── 2. Circuit Breaker ────────────────────────────────────────────────────
    hdr("2. Redis Circuit Breaker")

    from app.utils.redis_client import get_redis
    redis = await get_redis()
    cb_state    = (await redis.get("cb:fcm:state"))    or "closed"
    cb_failures = (await redis.get("cb:fcm:failures")) or "0"

    if cb_state == "open":
        err(f"Circuit breaker AÇIK! failures={cb_failures}")
        err("Sıfırla: redis-cli del cb:fcm:state cb:fcm:failures cb:fcm:opened_at")
    else:
        ok(f"Circuit breaker: {cb_state} (failures={cb_failures})")

    if not receiver.fcm_token:
        warn("\nFCM token olmadan push testi yapılamaz.")
        warn("Lütfen önce alıcı uygulamayı aç ve tekrar çalıştır.")
        await redis.aclose()
        return

    # ── 3. ARQ Pool — manuel başlat ──────────────────────────────────────────
    hdr("3. ARQ Pool Başlatma")

    from arq import create_pool
    from arq.connections import RedisSettings
    from app.config import settings as app_settings
    from app.core.task_queue import set_pool

    arq_pool = await create_pool(RedisSettings.from_dsn(app_settings.redis_url))
    set_pool(arq_pool)
    ok(f"ARQ pool başlatıldı → {app_settings.redis_url[:30]}…")

    # ── 4. push_notification() — tam pipeline ────────────────────────────────
    hdr("4. push_notification() — ARQ Pipeline Testi")

    from app.routers.notifications import push_notification

    queued_before = await redis.llen("arq:queue:default")
    info(f"ARQ kuyruk ÖNCE: {queued_before} iş")

    info("push_notification() çağrılıyor…")
    await push_notification(
        receiver.id,
        {
            "type": "message",
            "body": f"[Diagnostik] {sender_username} → pipeline testi",
            "sender_username": sender_username,
        },
        pref_key="messages",
    )

    await asyncio.sleep(1.0)
    queued_after = await redis.llen("arq:queue:default")
    diff = queued_after - queued_before
    info(f"ARQ kuyruk SONRA: {queued_after} iş ({diff:+d})")

    if diff > 0:
        ok(f"Kuyruğa {diff} iş eklendi — worker işleyecek")
        info("Worker logları: sudo journalctl -u teqlif-worker -f | grep -E '\\[FCM\\]|\\[Worker\\]'")
    else:
        warn("ARQ kuyruğuna iş EKLENMEDİ (veya worker anında işledi)")
        info("Uvicorn [PUSH] logu: sudo journalctl -u teqlif --no-pager | grep '\\[PUSH\\]'")

    # ── 5. send_push() — doğrudan Firebase ───────────────────────────────────
    hdr("5. send_push() — Doğrudan Firebase (ARQ bypass)")

    from app.services.firebase_service import send_push, InvalidFCMTokenError

    info(f"send_push() çağrılıyor → token={receiver.fcm_token[:25]}…")
    t = time.monotonic()
    try:
        await send_push(
            token=receiver.fcm_token,
            title=f"🔔 Diagnostik ({sender_username})",
            body="Bu bildirim doğrudan Firebase'e gönderildi (ARQ bypass)",
            notif_type="message",
            extra_data={"sender_id": str(sender.id), "sender_username": sender_username},
        )
        elapsed = (time.monotonic() - t) * 1000
        ok(f"Firebase yanıt verdi ({elapsed:.0f}ms)")
        print(f"\n  {BLD}Bu bildirim cihaza GELDİ mi?{RST}")
        print(f"  {GRN}EVET geldi{RST} → sorun ARQ pipeline'da (4. adımı incele)")
        print(f"  {RED}HAYIR gelmedi{RST} → sorun iOS/APNs veya cihaz bildirim ayarında\n")
    except InvalidFCMTokenError:
        err("FCM TOKEN GEÇERSİZ veya SÜRESİ DOLMUŞ!")
        err(f"  Temizle: UPDATE users SET fcm_token=NULL WHERE username='{receiver_username}';")
        err("  Sonra uygulamayı aç — yeni token otomatik kaydedilir")
    except Exception as exc:
        err(f"FCM hatası: {type(exc).__name__}: {exc}")
        import traceback; traceback.print_exc()

    # ── 6. Gerçek Mesaj — DB üzerinden ───────────────────────────────────────
    hdr("6. Gerçek Mesaj (DB) + Bildirim Pipeline")

    from app.models.message import DirectMessage
    from app.routers.notifications import push_notification as push_notif  # noqa: F811

    msg_content = f"[TEST {int(time.time())}] Diagnostik mesajı"

    async with AsyncSessionLocal() as db:
        msg = DirectMessage(
            sender_id=sender.id,
            receiver_id=receiver.id,
            content=msg_content,
            message_type="text",
        )
        db.add(msg)
        await db.commit()
        await db.refresh(msg)
        ok(f"Mesaj DB'ye eklendi (id={msg.id}): {msg_content}")

    q_before = await redis.llen("arq:queue:default")
    await push_notif(
        receiver.id,
        {
            "type": "message",
            "body": msg_content,
            "sender_username": sender_username,
            "related_id": str(msg.id),
        },
        pref_key="messages",
    )
    await asyncio.sleep(0.5)
    q_after = await redis.llen("arq:queue:default")
    info(f"Mesaj bildirimi ARQ: {q_after - q_before:+d} iş")

    # ── Özet ──────────────────────────────────────────────────────────────────
    hdr("ÖZET")
    ok(f"FCM token: mevcut") if receiver.fcm_token else err("FCM token: YOK")
    ok("Circuit breaker: kapalı") if cb_state != "open" else err(f"Circuit breaker: AÇIK")
    ok(f"ARQ pipeline: +{diff} iş") if diff > 0 else warn("ARQ pipeline: iş eklenmedi")
    print()
    info("Uvicorn yeniden başlatma gerekirse: sudo systemctl restart teqlif")
    print()

    await arq_pool.close()
    await redis.aclose()


if __name__ == "__main__":
    asyncio.run(main())
