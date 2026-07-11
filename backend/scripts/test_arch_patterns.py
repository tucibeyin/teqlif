#!/usr/bin/env python3
"""
Architectural Pattern Test Suite
Kullanım: python scripts/test_arch_patterns.py

Test edilen modüller:
  1. Circuit Breaker  — durum makinesi (CLOSED → OPEN → HALF_OPEN → CLOSED)
  2. Outbox Pattern   — Redis Stream yayın + replay
  3. CQRS Cache       — cache miss/hit/invalidate
  4. Saga             — başarılı akış + kompanzasyon
  5. Idempotency      — Redis katmanı (duplicate key tespiti)
"""
import asyncio
import json
import os
import sys
import time

# ── Path düzeltme (scripts/ içinden çalıştırılıyor) ──────────────────────────
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ── Renk çıktı ────────────────────────────────────────────────────────────────
G = "\033[92m"
R = "\033[91m"
Y = "\033[93m"
B = "\033[96m"
X = "\033[0m"

def ok(msg):   print(f"  {G}✔ {msg}{X}")
def err(msg):  print(f"  {R}✘ {msg}{X}")
def info(msg): print(f"  {B}→ {msg}{X}")
def head(msg): print(f"\n{Y}{'═'*60}\n  {msg}\n{'═'*60}{X}")

_passed = 0
_failed = 0


def assert_true(condition: bool, label: str):
    global _passed, _failed
    if condition:
        ok(label)
        _passed += 1
    else:
        err(f"BAŞARISIZ: {label}")
        _failed += 1


# ══════════════════════════════════════════════════════════════════════════════
# 1. CIRCUIT BREAKER
# ══════════════════════════════════════════════════════════════════════════════

async def test_circuit_breaker():
    head("1. Circuit Breaker")
    from app.core.circuit_breaker import CircuitBreaker, CircuitOpenError
    from app.utils.redis_client import get_redis

    redis = await get_redis()
    cb = CircuitBreaker(name="test_cb", failure_threshold=3, recovery_timeout=2)

    # Temizlik
    await redis.delete(cb._key_state, cb._key_failures, cb._key_opened_at)

    # ── CLOSED: normal çağrı geçmeli ─────────────────────────────────────────
    info("CLOSED durumda çağrı testi")
    call_reached = False
    try:
        async with cb:
            call_reached = True
            # başarılı çağrı simülasyonu
    except CircuitOpenError:
        pass
    assert_true(call_reached, "CLOSED: çağrı iletildi")

    # ── failure_threshold kadar hata → OPEN ───────────────────────────────────
    info("Eşik hatası → OPEN durumuna geçiş")
    for i in range(3):
        try:
            async with cb:
                raise ValueError(f"Simüle hata #{i+1}")
        except (ValueError, CircuitOpenError):
            pass

    state = await redis.get(cb._key_state)
    assert_true(state == "open", f"OPEN durumuna geçti (state={state})")

    # ── OPEN: çağrı reddedilmeli ──────────────────────────────────────────────
    info("OPEN durumda çağrı reddi testi")
    rejected = False
    try:
        async with cb:
            pass
    except CircuitOpenError:
        rejected = True
    assert_true(rejected, "OPEN: çağrı CircuitOpenError ile reddedildi")

    # ── Recovery timeout → HALF_OPEN ─────────────────────────────────────────
    info(f"Recovery timeout bekleniyor ({cb.recovery_timeout}s)...")
    # opened_at'ı geçmişe çekerek timeout simüle et
    past = str(time.time() - cb.recovery_timeout - 1)
    await redis.set(cb._key_opened_at, past)

    state = await cb._get_state()
    assert_true(state == "half_open", f"HALF_OPEN durumuna geçti (state={state})")

    # ── HALF_OPEN: başarılı çağrı → CLOSED ───────────────────────────────────
    info("HALF_OPEN → başarılı çağrı → CLOSED")
    try:
        async with cb:
            pass  # başarılı
    except CircuitOpenError:
        pass

    state = await redis.get(cb._key_state)
    assert_true(state is None, f"CLOSED'a döndü (state={state or 'None=closed'})")

    # ── .call() fallback ──────────────────────────────────────────────────────
    info(".call() fallback testi (circuit kapalı ama fonksiyon hata verir)")
    async def failing_func():
        raise ConnectionError("bağlantı yok")

    result = await cb.call(failing_func, fallback="FALLBACK")
    assert_true(result == "FALLBACK", f".call() fallback döndü: {result}")

    # Temizlik
    await redis.delete(cb._key_state, cb._key_failures, cb._key_opened_at)


# ══════════════════════════════════════════════════════════════════════════════
# 2. OUTBOX (Redis Stream)
# ══════════════════════════════════════════════════════════════════════════════

async def test_outbox():
    head("2. Outbox Pattern (Redis Stream)")
    from app.core.auction_outbox import outbox_publish, outbox_replay, _stream_key
    from app.utils.redis_client import get_redis

    redis = await get_redis()
    test_stream_id = 99999
    key = _stream_key(test_stream_id)
    await redis.delete(key)

    # ── Publish: event stream'e yazılmalı ────────────────────────────────────
    info("Event publish testi")
    events_to_publish = [
        {"type": "AUCTION_STATE", "status": "active", "bid_amount": 100},
        {"type": "NEW_BID", "bidder_id": 42, "amount": 150},
        {"type": "NEW_BID", "bidder_id": 7,  "amount": 200},
    ]
    for payload in events_to_publish:
        await outbox_publish(test_stream_id, payload)

    length = await redis.xlen(key)
    assert_true(length == 3, f"Stream'e 3 event yazıldı (xlen={length})")

    # ── TTL set edilmeli ──────────────────────────────────────────────────────
    ttl = await redis.ttl(key)
    assert_true(ttl > 0, f"Stream TTL ayarlandı (ttl={ttl}s)")

    # ── Replay: son N event doğru sırada gelmeli ─────────────────────────────
    info("Event replay testi")
    replayed = await outbox_replay(test_stream_id, count=10)
    assert_true(len(replayed) == 3, f"3 event replay edildi (count={len(replayed)})")

    # outbox_replay XREVRANGE kullanır (yeniden eskiye), listeyi tersine çevir
    first_type = replayed[-1].get("type")  # en eski event
    assert_true(first_type == "AUCTION_STATE", f"İlk event tipi doğru: {first_type}")

    last_amount = replayed[0].get("amount")  # en yeni event
    assert_true(last_amount == 200, f"Son event amount doğru: {last_amount}")

    # ── count sınırı ─────────────────────────────────────────────────────────
    replayed_limited = await outbox_replay(test_stream_id, count=2)
    assert_true(len(replayed_limited) == 2, f"count=2 limiti çalışıyor ({len(replayed_limited)} event)")

    # ── Var olmayan stream → boş liste ───────────────────────────────────────
    empty = await outbox_replay(88888, count=5)
    assert_true(empty == [], f"Olmayan stream → boş liste döndü")

    # Temizlik
    await redis.delete(key)


# ══════════════════════════════════════════════════════════════════════════════
# 3. CQRS CACHE-ASIDE
# ══════════════════════════════════════════════════════════════════════════════

async def test_cqrs_cache():
    head("3. CQRS Cache-Aside")
    from app.core.read_cache import cache_get, cache_set, invalidate_cache, _make_key
    from app.utils.redis_client import get_redis

    redis = await get_redis()
    ns = "test:listings"
    params = {"category": "electronics", "limit": 20, "offset": 0}

    # Temizlik
    for k in await redis.keys(f"cqrs:{ns}:*"):
        await redis.delete(k)

    # ── Cache miss ────────────────────────────────────────────────────────────
    info("Cache miss testi")
    result = await cache_get(ns, params)
    assert_true(result is None, "Cache miss → None döndü")

    # ── Cache set + hit ───────────────────────────────────────────────────────
    info("Cache set + hit testi")
    fake_data = [{"id": 1, "title": "iPhone"}, {"id": 2, "title": "MacBook"}]
    await cache_set(ns, params, fake_data, ttl=10)

    hit = await cache_get(ns, params)
    assert_true(hit is not None, "Cache hit → veri döndü")
    assert_true(len(hit) == 2, f"Doğru veri: {len(hit)} kayıt")
    assert_true(hit[0]["title"] == "iPhone", f"İçerik doğru: {hit[0]['title']}")

    # ── Farklı params → farklı key ────────────────────────────────────────────
    info("Farklı params → farklı cache key testi")
    params2 = {"category": "clothing", "limit": 20, "offset": 0}
    miss2 = await cache_get(ns, params2)
    assert_true(miss2 is None, "Farklı params → bağımsız cache (miss)")

    # ── TTL kontrolü ──────────────────────────────────────────────────────────
    key = _make_key(ns, params)
    ttl = await redis.ttl(key)
    assert_true(0 < ttl <= 10, f"TTL doğru aralıkta (ttl={ttl}s)")

    # ── Invalidate ────────────────────────────────────────────────────────────
    info("Cache invalidate testi")
    await cache_set(ns, params2, [{"id": 3}], ttl=10)
    deleted = await invalidate_cache(ns)
    assert_true(deleted == 2, f"2 key silindi (deleted={deleted})")

    after = await cache_get(ns, params)
    assert_true(after is None, "Invalidate sonrası cache miss")

    # Temizlik (zaten silindi)


# ══════════════════════════════════════════════════════════════════════════════
# 4. SAGA
# ══════════════════════════════════════════════════════════════════════════════

async def test_saga():
    head("4. Saga — Kompanzasyon")
    from app.core.saga import Saga, SagaError

    # ── Başarılı akış ─────────────────────────────────────────────────────────
    info("Başarılı saga akışı")
    log = []

    async def step_a(): log.append("do_a"); return "result_a"
    async def step_b(): log.append("do_b"); return "result_b"

    async with Saga("test_success") as saga:
        r_a = await saga.step("a", do=step_a, compensate=lambda: log.append("comp_a"))
        r_b = await saga.step("b", do=step_b, compensate=lambda: log.append("comp_b"))

    assert_true(r_a == "result_a", f"Adım A sonucu: {r_a}")
    assert_true(r_b == "result_b", f"Adım B sonucu: {r_b}")
    assert_true("comp_a" not in log and "comp_b" not in log,
                "Başarılı akışta kompanzasyon çalışmadı")

    # ── Adım başarısız → kompanzasyonlar ters sırayla ─────────────────────────
    info("Başarısız adım → kompanzasyon ters sırası testi")
    comp_log = []

    async def ok_a():   comp_log.append("do_a"); return "a"
    async def ok_b():   comp_log.append("do_b"); return "b"
    async def fail_c(): comp_log.append("do_c"); raise RuntimeError("C patladı")

    saga_err = None
    try:
        async with Saga("test_fail") as saga2:
            await saga2.step("a", do=ok_a,   compensate=lambda: comp_log.append("comp_a"))
            await saga2.step("b", do=ok_b,   compensate=lambda: comp_log.append("comp_b"))
            await saga2.step("c", do=fail_c, compensate=lambda: comp_log.append("comp_c"))
    except SagaError as e:
        saga_err = e

    assert_true(saga_err is not None, "SagaError fırlatıldı")
    assert_true("do_a" in comp_log and "do_b" in comp_log, "A ve B adımları çalıştı")
    assert_true("do_c" in comp_log, "C adımı çalıştı (hata verdi)")
    # Kompanzasyonlar ters sırada: B → A (C başarısız oldu, comp_c çalışmaz)
    assert_true("comp_b" in comp_log and "comp_a" in comp_log,
                "B ve A kompanzasyonları çalıştı")
    comp_order = [x for x in comp_log if x.startswith("comp_")]
    assert_true(comp_order == ["comp_b", "comp_a"],
                f"Kompanzasyon sırası doğru: {comp_order}")

    # ── commit() sonrası hata → __aexit__ kompanzasyonu ──────────────────────
    info("__aexit__ kompanzasyonu (step dışı hata)")
    exit_log = []

    async def ok_x(): exit_log.append("do_x"); return "x"

    try:
        async with Saga("test_exit") as saga3:
            await saga3.step("x", do=ok_x, compensate=lambda: exit_log.append("comp_x"))
            raise RuntimeError("commit sonrası patlama")
    except (RuntimeError, SagaError):
        pass

    assert_true("comp_x" in exit_log, "__aexit__ kompanzasyonu tetiklendi")

    # ── Kompanzasyonu None olan adım ─────────────────────────────────────────
    info("compensate=None adım güvenli atlama testi")
    none_log = []

    async def ok_n(): none_log.append("do_n"); return "n"
    async def fail_n(): raise RuntimeError("fail")

    try:
        async with Saga("test_none_comp") as saga4:
            await saga4.step("n", do=ok_n, compensate=None)
            await saga4.step("f", do=fail_n, compensate=None)
    except SagaError:
        pass

    assert_true("do_n" in none_log, "compensate=None adım hata vermeden atlandı")


# ══════════════════════════════════════════════════════════════════════════════
# 5. IDEMPOTENCY (Redis katmanı)
# ══════════════════════════════════════════════════════════════════════════════

async def test_idempotency():
    head("5. Idempotency (Redis katmanı)")
    from app.utils.redis_client import get_redis
    import uuid

    redis = await get_redis()
    scope = "bid"
    idem_key = f"test-{uuid.uuid4().hex[:8]}"
    redis_key = f"idempotency:{scope}:{idem_key}"

    # Temizlik
    await redis.delete(redis_key)

    # ── İlk istek → cache'de yok ──────────────────────────────────────────────
    info("İlk istek: cache miss testi")
    cached = await redis.get(redis_key)
    assert_true(cached is None, "İlk istekte cache yok")

    # ── Yanıtı cache'e yaz (store_idempotency_result simülasyonu) ─────────────
    info("Yanıt cache'e yazılıyor")
    response_data = {"status": "ok", "bid_id": 123, "amount": 500}
    await redis.set(
        redis_key,
        json.dumps({"body": response_data, "status_code": 200}),
        ex=30,
    )

    # ── İkinci istek → cache'den dönmeli ─────────────────────────────────────
    info("İkinci istek: cache hit testi")
    cached_raw = await redis.get(redis_key)
    assert_true(cached_raw is not None, "İkinci istekte cache hit")

    data = json.loads(cached_raw)
    assert_true(data["status_code"] == 200, f"Status code doğru: {data['status_code']}")
    assert_true(data["body"]["bid_id"] == 123, f"Yanıt gövdesi doğru: bid_id={data['body']['bid_id']}")

    # ── TTL kontrolü ──────────────────────────────────────────────────────────
    ttl = await redis.ttl(redis_key)
    assert_true(0 < ttl <= 30, f"TTL doğru aralıkta (ttl={ttl}s)")

    # ── Farklı key → bağımsız ─────────────────────────────────────────────────
    info("Farklı idempotency key → bağımsız testi")
    other_key = f"idempotency:{scope}:other-{uuid.uuid4().hex[:8]}"
    other = await redis.get(other_key)
    assert_true(other is None, "Farklı key → cache miss (çakışma yok)")

    # ── TTL dolunca temizleniyor ──────────────────────────────────────────────
    info("TTL=1s kısa ömürlü key testi")
    short_key = f"idempotency:{scope}:short-{uuid.uuid4().hex[:8]}"
    await redis.set(short_key, json.dumps({"body": {}, "status_code": 200}), ex=1)
    await asyncio.sleep(1.2)
    expired = await redis.get(short_key)
    assert_true(expired is None, "TTL sonrası key otomatik silindi")

    # Temizlik
    await redis.delete(redis_key)


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

async def run_test(name: str, coro):
    global _failed
    try:
        await coro
    except Exception as e:
        import traceback
        err(f"[{name}] Beklenmeyen hata: {e}")
        traceback.print_exc()
        _failed += 1


async def main():
    print(f"\n{Y}Teqlif Architectural Pattern Test Suite{X}")
    print(f"{B}{'─'*60}{X}")

    await run_test("Circuit Breaker", test_circuit_breaker())
    await run_test("Outbox",          test_outbox())
    await run_test("CQRS Cache",      test_cqrs_cache())
    await run_test("Saga",            test_saga())
    await run_test("Idempotency",     test_idempotency())

    # ── Özet ──────────────────────────────────────────────────────────────────
    total = _passed + _failed
    print(f"\n{Y}{'═'*60}{X}")
    print(f"  Sonuç: {G}{_passed} geçti{X} / {R}{_failed} başarısız{X} / {total} toplam")
    if _failed == 0:
        print(f"  {G}Tüm testler geçti.{X}")
    else:
        print(f"  {R}Başarısız test var — yukarıdaki hataları incele.{X}")
    print(f"{Y}{'═'*60}{X}\n")

    sys.exit(0 if _failed == 0 else 1)


if __name__ == "__main__":
    asyncio.run(main())
