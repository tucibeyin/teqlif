"""
Groq + Cerebras + Gemini API Bağlantı ve İşlevsellik Testi

Kullanım:
  python scripts/test_llm_apis.py             # tüm API'ler
  python scripts/test_llm_apis.py --groq      # sadece Groq
  python scripts/test_llm_apis.py --cerebras  # sadece Cerebras
  python scripts/test_llm_apis.py --gemini    # sadece Gemini
"""
import sys
import os
import asyncio
import argparse
import json
import time

# .env yükle
parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, parent)

try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(parent, ".env"))
except ImportError:
    pass  # dotenv yoksa os.environ'dan okur

import httpx

# ── Renkli terminal çıktısı ───────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
BLUE   = "\033[94m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):   print(f"  {GREEN}✓{RESET} {msg}")
def fail(msg): print(f"  {RED}✗{RESET} {msg}")
def warn(msg): print(f"  {YELLOW}⚠{RESET} {msg}")
def info(msg): print(f"  {BLUE}→{RESET} {msg}")
def sep(c="─", n=60): print(c * n)
def header(title):
    sep("═")
    print(f"{BOLD}  {title}{RESET}")
    sep("═")

# ── Test prompt ───────────────────────────────────────────────────────────────
TEST_SYSTEM = (
    "Sen bir ikinci el ilan platformunda satıcısın. "
    "Kısa, doğal Türkçe yaz."
)
TEST_USER = (
    "iPhone 14 Pro için 2 cümlelik ilan metni yaz. "
    "Birinci tekil şahıs kullan."
)

# ─────────────────────────────────────────────────────────────────────────────
#  GROQ TESTLERİ
# ─────────────────────────────────────────────────────────────────────────────

GROQ_BASE = "https://api.groq.com/openai/v1"
GROQ_MODEL = "llama-3.3-70b-versatile"

async def test_groq(key: str) -> bool:
    """Groq API testlerini çalıştırır. True → tüm testler geçti."""
    header("GROQ — llama-3.3-70b-versatile")
    all_passed = True

    # ── Test 1: API key format ────────────────────────────────────────────────
    print(f"\n  Test 1: API key format kontrolü")
    if key.startswith("gsk_") and len(key) > 20:
        ok(f"Format geçerli ({len(key)} karakter)")
    else:
        fail(f"Beklenmeyen format — 'gsk_...' ile başlamalı (mevcut: '{key[:8]}...')")
        warn("Groq testleri devam ediyor ama başarısız olabilir")
        all_passed = False

    # ── Test 2: Model listesi (auth + network) ────────────────────────────────
    print(f"\n  Test 2: Bağlantı ve kimlik doğrulama (GET /models)")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            t0 = time.perf_counter()
            resp = await client.get(
                f"{GROQ_BASE}/models",
                headers={"Authorization": f"Bearer {key}"},
            )
            latency = (time.perf_counter() - t0) * 1000

        if resp.status_code == 200:
            models = resp.json().get("data", [])
            model_ids = [m["id"] for m in models]
            ok(f"Bağlantı başarılı — {len(models)} model listelendi ({latency:.0f}ms)")
            if GROQ_MODEL in model_ids:
                ok(f"{GROQ_MODEL} mevcut")
            else:
                warn(f"{GROQ_MODEL} listede yok — mevcut modeller: {model_ids[:3]}...")
                all_passed = False
        elif resp.status_code == 401:
            fail(f"401 Unauthorized — API key geçersiz veya süresi dolmuş")
            return False
        elif resp.status_code == 403:
            fail(f"403 Forbidden — Bu endpoint için yetki yok")
            all_passed = False
        else:
            fail(f"HTTP {resp.status_code} — {resp.text[:120]}")
            all_passed = False
    except httpx.ConnectError as e:
        fail(f"Bağlantı hatası — sunucuya ulaşılamıyor: {e}")
        return False
    except httpx.TimeoutException:
        fail(f"Timeout — 10 saniye içinde yanıt gelmedi")
        return False

    # ── Test 3: Chat completion (non-streaming) ───────────────────────────────
    print(f"\n  Test 3: Chat completion (streaming=False)")
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            t0 = time.perf_counter()
            resp = await client.post(
                f"{GROQ_BASE}/chat/completions",
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": TEST_SYSTEM},
                        {"role": "user",   "content": TEST_USER},
                    ],
                    "temperature": 0.3,
                    "max_tokens": 80,
                    "stream": False,
                },
            )
            elapsed = time.perf_counter() - t0

        if resp.status_code == 200:
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
            usage = data.get("usage", {})
            ok(f"Yanıt alındı ({elapsed:.2f}s)")
            ok(f"Token: {usage.get('prompt_tokens',0)} giriş / "
               f"{usage.get('completion_tokens',0)} çıkış")
            info(f"Çıktı: {content[:120]}")
        elif resp.status_code == 429:
            warn("429 Rate limit — kota dolmuş, biraz bekle")
            all_passed = False
        elif resp.status_code == 401:
            fail("401 Unauthorized — API key hatalı")
            return False
        else:
            fail(f"HTTP {resp.status_code}: {resp.text[:200]}")
            all_passed = False
    except httpx.TimeoutException:
        fail("Timeout — 30 saniye içinde yanıt gelmedi")
        all_passed = False

    # ── Test 4: Streaming ─────────────────────────────────────────────────────
    print(f"\n  Test 4: Streaming (SSE)")
    try:
        chunks = []
        first_token_t = None
        t0 = time.perf_counter()

        async with httpx.AsyncClient(timeout=30.0) as client:
            async with client.stream(
                "POST",
                f"{GROQ_BASE}/chat/completions",
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": TEST_SYSTEM},
                        {"role": "user",   "content": TEST_USER},
                    ],
                    "temperature": 0.3,
                    "max_tokens": 80,
                    "stream": True,
                },
            ) as resp:
                if resp.status_code != 200:
                    body = await resp.aread()
                    fail(f"HTTP {resp.status_code}: {body[:200]}")
                    all_passed = False
                else:
                    async for line in resp.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        raw = line[6:].strip()
                        if raw == "[DONE]":
                            break
                        try:
                            delta = json.loads(raw)["choices"][0]["delta"].get("content", "")
                            if delta:
                                if first_token_t is None:
                                    first_token_t = time.perf_counter()
                                chunks.append(delta)
                        except (json.JSONDecodeError, KeyError):
                            pass

        if chunks:
            ttft = (first_token_t - t0) if first_token_t else 0
            total = time.perf_counter() - t0
            text = "".join(chunks)
            ok(f"Stream başarılı — {len(chunks)} chunk, {len(text)} karakter")
            ok(f"İlk token: {ttft:.2f}s | Toplam: {total:.2f}s")
            info(f"Çıktı: {text[:120]}")
        else:
            fail("Stream'den içerik gelmedi")
            all_passed = False
    except httpx.TimeoutException:
        fail("Streaming timeout")
        all_passed = False

    return all_passed


# ─────────────────────────────────────────────────────────────────────────────
#  GEMINI TESTLERİ
# ─────────────────────────────────────────────────────────────────────────────

GEMINI_BASE  = "https://generativelanguage.googleapis.com/v1beta"
GEMINI_MODEL = "gemini-2.0-flash"

async def test_gemini(key: str) -> bool:
    """Gemini API testlerini çalıştırır. True → tüm testler geçti."""
    header("GEMINI — gemini-2.0-flash")
    all_passed = True

    # ── Test 1: API key format ────────────────────────────────────────────────
    print(f"\n  Test 1: API key format kontrolü")
    # Google API key formatları: eski → AIza..., yeni → AQ.Ab8R...
    if len(key) > 20:
        ok(f"Format geçerli ({len(key)} karakter)")
    else:
        fail(f"Key çok kısa ({len(key)} karakter) — Google AI Studio'dan tekrar al")
        all_passed = False

    # ── Test 2: Model listesi (auth + network) ────────────────────────────────
    print(f"\n  Test 2: Bağlantı ve kimlik doğrulama (GET /models)")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            t0 = time.perf_counter()
            resp = await client.get(
                f"{GEMINI_BASE}/models",
                params={"key": key},
            )
            latency = (time.perf_counter() - t0) * 1000

        if resp.status_code == 200:
            models = resp.json().get("models", [])
            names = [m["name"].split("/")[-1] for m in models]
            ok(f"Bağlantı başarılı — {len(models)} model listelendi ({latency:.0f}ms)")
            if any(GEMINI_MODEL in n for n in names):
                ok(f"{GEMINI_MODEL} mevcut")
            else:
                warn(f"{GEMINI_MODEL} listede yok")
                flash_models = [n for n in names if "flash" in n.lower()]
                if flash_models:
                    warn(f"Mevcut flash modeller: {flash_models[:3]}")
                all_passed = False
        elif resp.status_code == 400:
            fail(f"400 Bad Request — API key formatı hatalı")
            return False
        elif resp.status_code == 403:
            fail(f"403 Forbidden — API key geçersiz veya izin yok")
            return False
        else:
            fail(f"HTTP {resp.status_code} — {resp.text[:120]}")
            all_passed = False
    except httpx.ConnectError as e:
        fail(f"Bağlantı hatası: {e}")
        return False
    except httpx.TimeoutException:
        fail("Timeout — 10 saniye içinde yanıt gelmedi")
        return False

    # ── Test 3: Content generation (non-streaming) ────────────────────────────
    print(f"\n  Test 3: İçerik üretimi (streaming=False)")
    endpoint = f"{GEMINI_BASE}/models/{GEMINI_MODEL}:generateContent"
    payload = {
        "system_instruction": {"parts": [{"text": TEST_SYSTEM}]},
        "contents": [{"role": "user", "parts": [{"text": TEST_USER}]}],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 80,
        },
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            t0 = time.perf_counter()
            resp = await client.post(
                endpoint,
                params={"key": key},
                json=payload,
            )
            elapsed = time.perf_counter() - t0

        if resp.status_code == 200:
            data = resp.json()
            try:
                content = data["candidates"][0]["content"]["parts"][0]["text"]
                usage = data.get("usageMetadata", {})
                ok(f"Yanıt alındı ({elapsed:.2f}s)")
                ok(f"Token: {usage.get('promptTokenCount',0)} giriş / "
                   f"{usage.get('candidatesTokenCount',0)} çıkış")
                info(f"Çıktı: {content[:120]}")
            except (KeyError, IndexError) as e:
                fail(f"Yanıt parse hatası: {e} — {str(data)[:200]}")
                all_passed = False
        elif resp.status_code == 429:
            warn("429 Rate limit — dakika kotası dolmuş, bekle")
            all_passed = False
        elif resp.status_code == 400:
            err = resp.json().get("error", {})
            fail(f"400 Bad Request: {err.get('message','')[:200]}")
            all_passed = False
        elif resp.status_code == 404:
            fail(f"404 Not Found — model bulunamadı: {GEMINI_MODEL}")
            warn("Alternatif dene: gemini-1.5-flash")
            all_passed = False
        else:
            fail(f"HTTP {resp.status_code}: {resp.text[:200]}")
            all_passed = False
    except httpx.TimeoutException:
        fail("Timeout — 30 saniye içinde yanıt gelmedi")
        all_passed = False

    # ── Test 4: Streaming (SSE) ───────────────────────────────────────────────
    print(f"\n  Test 4: Streaming (SSE)")
    info("3 saniye bekleniyor (rate limit koruması)...")
    await asyncio.sleep(3)
    stream_endpoint = f"{GEMINI_BASE}/models/{GEMINI_MODEL}:streamGenerateContent"
    try:
        chunks = []
        first_token_t = None
        t0 = time.perf_counter()

        async with httpx.AsyncClient(timeout=30.0) as client:
            async with client.stream(
                "POST",
                stream_endpoint,
                params={"key": key, "alt": "sse"},
                json=payload,
            ) as resp:
                if resp.status_code != 200:
                    body = await resp.aread()
                    fail(f"HTTP {resp.status_code}: {body[:200]}")
                    all_passed = False
                else:
                    async for line in resp.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        raw = line[6:].strip()
                        try:
                            data = json.loads(raw)
                            text = (
                                data.get("candidates", [{}])[0]
                                    .get("content", {})
                                    .get("parts", [{}])[0]
                                    .get("text", "")
                            )
                            if text:
                                if first_token_t is None:
                                    first_token_t = time.perf_counter()
                                chunks.append(text)
                        except (json.JSONDecodeError, IndexError):
                            pass

        if chunks:
            ttft = (first_token_t - t0) if first_token_t else 0
            total = time.perf_counter() - t0
            text = "".join(chunks)
            ok(f"Stream başarılı — {len(chunks)} chunk, {len(text)} karakter")
            ok(f"İlk token: {ttft:.2f}s | Toplam: {total:.2f}s")
            info(f"Çıktı: {text[:120]}")
        else:
            fail("Stream'den içerik gelmedi")
            all_passed = False
    except httpx.TimeoutException:
        fail("Streaming timeout")
        all_passed = False

    return all_passed


# ─────────────────────────────────────────────────────────────────────────────
#  CEREBRAS TESTLERİ
# ─────────────────────────────────────────────────────────────────────────────

CEREBRAS_BASE  = "https://api.cerebras.ai/v1"
CEREBRAS_MODEL = "gpt-oss-120b"

async def test_cerebras(key: str) -> bool:
    """Cerebras API testlerini çalıştırır. True → tüm testler geçti."""
    header("CEREBRAS — llama-3.3-70b")
    all_passed = True

    # ── Test 1: API key format ────────────────────────────────────────────────
    print(f"\n  Test 1: API key format kontrolü")
    if key.startswith("csk-") and len(key) > 20:
        ok(f"Format geçerli ({len(key)} karakter)")
    else:
        fail(f"Beklenmeyen format — 'csk_...' ile başlamalı (mevcut: '{key[:8]}...')")
        warn("Cerebras testleri devam ediyor ama başarısız olabilir")
        all_passed = False

    # ── Test 2: Model listesi (auth + network) ────────────────────────────────
    print(f"\n  Test 2: Bağlantı ve kimlik doğrulama (GET /models)")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            t0 = time.perf_counter()
            resp = await client.get(
                f"{CEREBRAS_BASE}/models",
                headers={"Authorization": f"Bearer {key}"},
            )
            latency = (time.perf_counter() - t0) * 1000

        if resp.status_code == 200:
            models = resp.json().get("data", [])
            model_ids = [m["id"] for m in models]
            ok(f"Bağlantı başarılı — {len(models)} model listelendi ({latency:.0f}ms)")
            if CEREBRAS_MODEL in model_ids:
                ok(f"{CEREBRAS_MODEL} mevcut")
            else:
                warn(f"{CEREBRAS_MODEL} listede yok — mevcut modeller: {model_ids[:5]}")
                all_passed = False
        elif resp.status_code == 401:
            fail(f"401 Unauthorized — API key geçersiz")
            return False
        else:
            fail(f"HTTP {resp.status_code} — {resp.text[:120]}")
            all_passed = False
    except httpx.ConnectError as e:
        fail(f"Bağlantı hatası: {e}")
        return False
    except httpx.TimeoutException:
        fail("Timeout — 10 saniye içinde yanıt gelmedi")
        return False

    # ── Test 3: Content generation (non-streaming) ────────────────────────────
    print(f"\n  Test 3: İçerik üretimi (streaming=False)")
    payload = {
        "model": CEREBRAS_MODEL,
        "messages": [
            {"role": "system", "content": TEST_SYSTEM},
            {"role": "user",   "content": TEST_USER},
        ],
        "temperature": 0.3,
        "max_tokens": 80,
        "stream": False,
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            t0 = time.perf_counter()
            resp = await client.post(
                f"{CEREBRAS_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            elapsed = time.perf_counter() - t0

        if resp.status_code == 200:
            data = resp.json()
            try:
                content = data["choices"][0]["message"]["content"]
                usage = data.get("usage", {})
                ok(f"Yanıt alındı ({elapsed:.2f}s)")
                ok(f"Token: {usage.get('prompt_tokens',0)} giriş / "
                   f"{usage.get('completion_tokens',0)} çıkış")
                info(f"Çıktı: {content[:120]}")
            except (KeyError, IndexError) as e:
                fail(f"Yanıt parse hatası: {e}")
                all_passed = False
        elif resp.status_code == 429:
            warn("429 Rate limit — biraz bekle ve tekrar dene")
            all_passed = False
        elif resp.status_code == 401:
            fail("401 Unauthorized — API key geçersiz")
            return False
        else:
            fail(f"HTTP {resp.status_code}: {resp.text[:200]}")
            all_passed = False
    except httpx.TimeoutException:
        fail("Timeout — 30 saniye içinde yanıt gelmedi")
        all_passed = False

    # ── Test 4: Streaming ─────────────────────────────────────────────────────
    print(f"\n  Test 4: Streaming (SSE)")
    stream_payload = {**payload, "stream": True}
    try:
        chunks = []
        first_token_t = None
        t0 = time.perf_counter()

        async with httpx.AsyncClient(timeout=30.0) as client:
            async with client.stream(
                "POST",
                f"{CEREBRAS_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=stream_payload,
            ) as resp:
                if resp.status_code != 200:
                    body = await resp.aread()
                    fail(f"HTTP {resp.status_code}: {body[:200]}")
                    all_passed = False
                else:
                    async for line in resp.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        raw = line[6:].strip()
                        if raw == "[DONE]":
                            break
                        try:
                            delta = json.loads(raw)["choices"][0]["delta"].get("content", "")
                            if delta:
                                if first_token_t is None:
                                    first_token_t = time.perf_counter()
                                chunks.append(delta)
                        except (json.JSONDecodeError, KeyError, IndexError):
                            pass

        if chunks:
            ttft = (first_token_t - t0) if first_token_t else 0
            total = time.perf_counter() - t0
            text = "".join(chunks)
            ok(f"Stream başarılı — {len(chunks)} chunk, {len(text)} karakter")
            ok(f"İlk token: {ttft:.2f}s | Toplam: {total:.2f}s")
            info(f"Çıktı: {text[:120]}")
        else:
            fail("Stream'den içerik gelmedi")
            all_passed = False
    except httpx.TimeoutException:
        fail("Streaming timeout")
        all_passed = False

    return all_passed


# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────

async def main(run_groq: bool, run_cerebras: bool, run_gemini: bool) -> None:
    results: dict[str, bool] = {}

    # ── Groq ──────────────────────────────────────────────────────────────────
    if run_groq:
        groq_key = os.environ.get("GROQ_API_KEY", "")
        if not groq_key:
            header("GROQ")
            fail("GROQ_API_KEY bulunamadı — .env dosyasını kontrol et")
            results["Groq"] = False
        else:
            results["Groq"] = await test_groq(groq_key)

    # ── Cerebras ──────────────────────────────────────────────────────────────
    if run_cerebras:
        cerebras_key = os.environ.get("CEREBRAS_API_KEY", "")
        if not cerebras_key:
            header("CEREBRAS")
            fail("CEREBRAS_API_KEY bulunamadı — .env dosyasını kontrol et")
            results["Cerebras"] = False
        else:
            results["Cerebras"] = await test_cerebras(cerebras_key)

    # ── Gemini ────────────────────────────────────────────────────────────────
    if run_gemini:
        gemini_key = os.environ.get("GEMINI_API_KEY", "")
        if not gemini_key:
            header("GEMINI")
            fail("GEMINI_API_KEY bulunamadı — .env dosyasını kontrol et")
            results["Gemini"] = False
        else:
            results["Gemini"] = await test_gemini(gemini_key)

    # ── Özet ──────────────────────────────────────────────────────────────────
    print()
    sep("═")
    print(f"{BOLD}  SONUÇ{RESET}")
    sep("═")
    for name, passed in results.items():
        status = f"{GREEN}BAŞARILI{RESET}" if passed else f"{RED}BAŞARISIZ{RESET}"
        print(f"  {name:12s} → {status}")
    sep("═")
    print()

    if not all(results.values()):
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Groq + Cerebras + Gemini API bağlantı testi")
    parser.add_argument("--groq",      action="store_true", help="Sadece Groq test et")
    parser.add_argument("--cerebras",  action="store_true", help="Sadece Cerebras test et")
    parser.add_argument("--gemini",    action="store_true", help="Sadece Gemini test et")
    args = parser.parse_args()

    any_flag = args.groq or args.cerebras or args.gemini
    run_groq      = args.groq     or not any_flag
    run_cerebras  = args.cerebras or not any_flag
    run_gemini    = args.gemini   or not any_flag

    asyncio.run(main(run_groq, run_cerebras, run_gemini))
