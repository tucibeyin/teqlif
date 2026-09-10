# Teqlif Scale V1.2 — Plan

> **Hedef:** node2 (RackNerd Buffalo, USA) topolojiye eklenerek AI açıklama üretimi dedicated bir proxy worker'a taşınır.  
> **Baseline:** V1.1 aktif (2026-09-08). Bu plan V1.1 üzerine değişkenleri listeler.  
> **Durum:** Planlama — henüz uygulanmadı.

---

## 1. Motivasyon

### Neden node2?

| Bulgu | Detay |
|---|---|
| **Gemini free tier EU kısıtlaması** | node1 Frankfurt IP'sinden Gemini API model listesi boş dönüyor (HTTP 403 / 0 model) |
| **node2 US IP'den Gemini erişimi** | 52 model — `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite` dahil tam erişim |
| **Groq geografik fark** | Yok — her iki IP'den 14 model, aynı kota |
| **Mevcut sessiz hata** | `llm_service.py` Gemini fallback, node1'den hiç çalışmamış; tüm üretim yükü Groq'a düşmüş |
| **node1 yük boşaltma** | Her AI isteği ~10–20 saniye httpx bağlantısı tutar; dedicated node'a taşınır |

### Coğrafi test sonucu (2026-09-10)

```
node1 (Frankfurt) → Gemini model listesi: 0 model
node2 (Buffalo)   → Gemini model listesi: 52 model  ✅
node1 (Frankfurt) → Groq model listesi:  14 model
node2 (Buffalo)   → Groq model listesi:  14 model (aynı)
```

---

## 2. Donanım

### node2 — RackNerd Buffalo (AI Proxy)

| Parametre | Değer |
|---|---|
| Sağlayıcı | RackNerd LLC |
| Lokasyon | Buffalo, NY, ABD |
| Hostname | node-ai |
| İşletim sistemi | Debian 13 (Trixie) / Kernel 6.12 |
| CPU | Intel Xeon E5-2670 v2 (1 çekirdek @ 2.50 GHz) |
| RAM | 1.4 GiB + 2 GiB Swap |
| Disk | 14.7 GiB |
| Ağ | ~237–435 Mbps uplink, ~82–86 ms ping to EU |
| Geekbench 6 | 206 single / 199 multi |
| WireGuard IP | **10.10.0.3** |

### Mevcut node'lar (V1.1 baseline)

| Node | Public IP | WireGuard IP | Rol |
|---|---|---|---|
| node1 | 135.125.175.223 | 10.10.0.1 | Ana backend |
| gateway | 94.16.105.135 | 10.10.0.2 | Edge proxy + observability |
| **node2** | TBD (RackNerd) | **10.10.0.3** | AI proxy — **Yeni** |

---

## 3. API Kota Referansı (Free Tier, 2026-09-10)

### 3.1 Groq — Chat Completions

> Kaynak: https://console.groq.com/settings/limits  
> Kota: organizasyon bazında (API key'e bağlı), IP'den bağımsız.

| Model | RPM | RPD | TPM | TPD | Kullanım |
|---|---|---|---|---|---|
| openai/gpt-oss-120b | 30 | 1.000 | 8K | 200K | ✅ Primary chain |
| openai/gpt-oss-20b | 30 | 1.000 | 8K | 200K | ✅ Primary chain |
| qwen/qwen3.6-27b | 30 | 1.000 | 8K | 200K | ✅ Primary chain |
| qwen/qwen3.8-27b | 30 | 1.000 | 8K | 200K | ✅ Primary chain |
| groq/compound | 30 | 250 | 70K | — | ✅ Primary chain |
| groq/compound-mini | 30 | 250 | 70K | — | ✅ Primary chain |
| allam-2-7b | 30 | 7.000 | 6K | 500K | ❌ Arapça model, uygun değil |
| openai/gpt-oss-safeguard-20b | 30 | 1.000 | 8K | 200K | ❌ Safety classifier |
| meta-llama/llama-prompt-guard-* | 30 | 14.4K | 15K | 500K | ❌ Safety classifier |
| whisper-large-v3* | 20 | 2.000 | — | — | ❌ STT |
| canopylabs/orpheus-* | 10 | 100 | — | — | ❌ TTS |

### 3.2 Gemini — Text-out Modeller

> Kaynak: https://aistudio.google.com/rate-limit  
> **Yalnızca US IP'den (node2) erişilebilir. EU IP (node1) bloke.**

| Model | RPM | TPM | RPD | Öneri |
|---|---|---|---|---|
| Gemini 3.5 Flash Lite | 15 | 250K | **500** | ✅ Fallback 1 — en yüksek RPD, güncel model |
| Gemini 3.1 Flash Lite | 15 | 250K | **500** | ✅ Fallback 2 — mevcut kodda var |
| Gemma 4 26B | 30 | 16K | 14.4K | 🔍 Test edilmeli — yüksek RPD ama Groq'ta yok |
| Gemma 4 31B | 30 | 16K | 14.4K | 🔍 Test edilmeli |
| Gemini 3.8/3.7/3.6/3.5 Flash | 5 | 250K | 20 | ⚠️ RPD çok düşük |
| Gemini 2.5 Flash | 5 | 250K | 20 | ⚠️ RPD çok düşük |

### 3.3 LLM Zinciri (node2 üzerinden)

```
node2 (US IP) — tam zincir:
  1. Groq openai/gpt-oss-120b     1.000 RPD
  2. Groq openai/gpt-oss-20b      1.000 RPD
  3. Groq qwen/qwen3.6-27b        1.000 RPD
  4. Groq qwen/qwen3.8-27b        1.000 RPD
  5. Groq groq/compound             250 RPD
  6. Groq groq/compound-mini        250 RPD
  ──────────────────────────────────────────
  7. Gemini 3.5 Flash Lite          500 RPD  ← US IP'de çalışır, EU'da bloke
  8. Gemini 3.1 Flash Lite          500 RPD  ← US IP'de çalışır, EU'da bloke
  9. Gemma 4 26B (Gemini API)    14.400 RPD  ← son çare; TPM=16K → etkin ~18 RPM
  ══════════════════════════════════════════
  Toplam                        ~19.900 RPD/gün

node2 DOWN → node1 lokal fallback (EU IP):
  1–6. Aynı Groq chain            ~4.500 RPD  (Gemini/Gemma EU'da çalışmaz)
```

**Gemma 4 not:** 14.400 RPD yüksek ama TPM=16K kısıtlı. Her istek ~850 token (prompt+output) → etkin kapasite ~18 RPM. Günlük doluluk senaryosunda son çare olarak yeterli.

---

## 4. Mimari Tasarım

### 4.1 WireGuard Topolojisi (Full Mesh)

**V1.1 (mevcut):**
```
gateway (10.10.0.2) ──── node1 (10.10.0.1)
```

**V1.2 (hedef):**
```
gateway (10.10.0.2) ──── node1 (10.10.0.1)
         \                    /
          ──── node2 (10.10.0.3) ────
```

Her peer diğer ikisini tanır. Mevcut gateway ↔ node1 tüneli değişmez.

### 4.2 Trafik Akışı (AI Açıklama Üretimi)

```
Mobil
  │ POST /api/listings/generate-description
  ▼
gateway (nginx) → WireGuard → node1:8000 (FastAPI)
  │
  ├─ Kredi/limit kontrolü
  ├─ async HTTP POST → 10.10.0.3:8080   (WireGuard tüneli, X-Internal-Token)
  │     │
  │     ▼ node2 FastAPI AI proxy
  │     ├─ Groq chain → Gemini fallback (US IP)
  │     └─ Tam metin döner → node1
  │
  ├─ node2 erişilemez / timeout (45s) → lokal fallback (Groq only, EU IP)
  ├─ Başarılı yanıt → kredi düş
  └─ JSON response → Mobil (tam metin, artık SSE değil)
```

### 4.3 Mimari Kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| **API çağrı modu** | **Non-streaming** (tam metin) | Groq `stream=False`, Gemini `generateContent` endpoint; animasyon client-side yapılacak, streaming gereksiz |
| **Typing animasyonu** | **Client-side** (Flutter) | API'den tam metin alınır; Flutter istediği animasyonu uygular — daha tutarlı, jitter yok |
| Proxy vs ARQ | **HTTP Proxy** | Stateless; node2 Redis/DB'ye erişmez; fallback trivial |
| Kredi düşme zamanı | **Başarılı yanıt sonrası** | Yarım/hatalı yanıt için ücret alınmaz |
| Fallback | **node2 down → node1 lokal çağrı** | Groq EU'dan çalışır (~4.500 RPD, Gemini/Gemma yok) |
| Auth | **X-Internal-Token header** | WireGuard şifreleme + shared secret: çift katman |
| node2 servis portu | **10.10.0.3:8080** (WireGuard IP'de) | Kamuya açık port yok |
| Kod tabanı | **Mono repo** (aynı git pull) | node2 `ai_proxy_main.py`'ı çalıştırır; `llm_service.py` paylaşılır |
| node2 `.env` | Mevcut şablona yeni key'ler eklenir | `DATABASE_URL`/`SECRET_KEY` placeholder; `GROQ_API_KEY`, `GEMINI_API_KEY`, `NODE2_INTERNAL_TOKEN` gerçek değer |

---

## 5. Servis Dağılımı (V1.2)

| Servis | node1 | gateway | node2 | Gerekçe |
|---|---|---|---|---|
| FastAPI prod (:8000) | ✅ | ❌ | ❌ | |
| FastAPI staging (:8001) | ✅ | ❌ | ❌ | |
| PostgreSQL | ✅ | ❌ | ❌ | |
| Redis | ✅ | ❌ | ❌ | |
| MinIO | ✅ | ❌ | ❌ | |
| ClickHouse | ✅ | ❌ | ❌ | |
| LiveKit SFU | ✅ | ❌ | ❌ | |
| ARQ Worker (genel + critical) | ✅ | ❌ | ❌ | |
| **AI Proxy (:8080)** | ❌ | ❌ | ✅ | **Yeni** — US IP, Gemini erişimi |
| nginx (public SSL + microcache) | ❌ | ✅ | ❌ | |
| nginx (uploads.teqlif.com) | ✅ | ❌ | ❌ | |
| Prometheus | ❌ | ✅ | ❌ | |
| Alertmanager | ❌ | ✅ | ❌ | |
| Loki | ❌ | ✅ | ❌ | |
| promtail | ✅ | ✅ | ✅ | Her node'da |
| node_exporter | ✅ | ✅ | ✅ | Her node'da |
| WireGuard | 10.10.0.1 | 10.10.0.2 | 10.10.0.3 | Full mesh |
| fail2ban | ✅ | ✅ | ✅ | |

---

## 6. Değişiklikler — Node Bazında

### 6.1 node2 (Yeni Kurulum)

**WireGuard `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
Address = 10.10.0.3/24
ListenPort = 51820
PrivateKey = <NODE2_PRIVATE_KEY>

[Peer]  # node1
PublicKey = <NODE1_PUBLIC_KEY>
AllowedIPs = 10.10.0.1/32
Endpoint = 135.125.175.223:51820
PersistentKeepalive = 25

[Peer]  # gateway
PublicKey = <GATEWAY_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32
Endpoint = 94.16.105.135:51820
PersistentKeepalive = 25
```

**UFW:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 51820/udp                              # WireGuard
ufw allow from 10.10.0.1 to any port 8080        # AI proxy ← node1
ufw allow from 10.10.0.2 to any port 9100        # node_exporter ← gateway Prometheus
```

**Servisler:**
```
/var/www/teqlif.com/               (git pull — mevcut repo)
/var/www/teqlif.com/backend/.env   (GROQ_API_KEY, GEMINI_API_KEY, NODE2_INTERNAL_TOKEN)

systemd:
  teqlif-ai-proxy.service  → uvicorn app.ai_proxy_main:app --host 10.10.0.3 --port 8080
  node_exporter.service
  promtail.service
```

### 6.2 node1 (Mevcut — Eklemeler)

**WireGuard:** node2 peer ekleme
```ini
# /etc/wireguard/wg0.conf'a eklenecek
[Peer]  # node2
PublicKey = <NODE2_PUBLIC_KEY>
AllowedIPs = 10.10.0.3/32
```

**UFW:** Ek kural gerekmez. node1 → node2:8080 outbound (varsayılan allow outgoing).

**Backend kod değişiklikleri:**
- `backend/app/config.py`: `node2_ai_proxy_url`, `node2_internal_token` alanları
- `backend/app/services/ml/llm_service.py`: non-streaming wrapper `generate_listing_description()` ekleme
- `backend/app/services/ml/ai_proxy_client.py`: yeni — node2 HTTP çağrısı + lokal fallback
- `backend/app/routers/listings.py`: SSE endpoint → JSON response; `ai_proxy_client` entegrasyonu
- `backend/app/ai_proxy_main.py`: yeni — node2'nin çalıştırdığı minimal FastAPI app

### 6.3 gateway (Mevcut — Eklemeler)

**WireGuard:** node2 peer ekleme
```ini
# /etc/wireguard/wg0.conf'a eklenecek
[Peer]  # node2
PublicKey = <NODE2_PUBLIC_KEY>
AllowedIPs = 10.10.0.3/32
Endpoint = <NODE2_PUBLIC_IP>:51820
PersistentKeepalive = 25
```

**UFW:** node2 promtail'ın Loki'ye push yapabilmesi için:
```bash
ufw allow from 10.10.0.3 to any port 3100   # Loki push ← node2 promtail
```

**`prometheus.yml`:** node2 scrape target ekleme
```yaml
- job_name: 'node-node2'
  static_configs:
    - targets: ['10.10.0.3:9100']
      labels:
        node: node2
```

---

## 7. Backend Kod Tasarımı

### Non-streaming + API-driven kota ilkesi

Groq ve Gemini her ikisi de tam metni tek HTTP yanıtında döndürebilir. `llm_service.py`'deki mevcut `stream=True` / `streamGenerateContent` yapısı kaldırılır; yerine basit `await response.json()` çağrıları gelir. `AsyncGenerator`, `_sentence_stream`, sentinel token'lar (`__META_groq__`, `__LLM_ERROR__`) ve SSE parsing tamamen ortadan kalkar. Post-processing (`_RE_AI_OPENER` temizleme, fiyat suffix) full string üzerinde yapılır.

**Kota yönetimi:** Redis counter veya header tracking yok. API'nin kendi 429 yanıtı kota kontrolcüsüdür. Her model sırayla denenir; 429 gelirse bir sonrakine geçilir. Tüm modeller 429 dönerse `503 — Şu an bu özellik kullanılamıyor.`

### In-memory exhaustion tracking

429'u her seferinde yeniden almak yerine, exhausted modeller process memory'de saklanır. Aynı process içinde sıradaki request doğrudan atlar — 429 latency sıfıra iner.

```python
import time
_exhausted: dict[str, float] = {}   # {model_id: reset_epoch_seconds}

def _is_exhausted(model_id: str) -> bool:
    ts = _exhausted.get(model_id)
    if ts is None:
        return False
    if time.time() >= ts:
        _exhausted.pop(model_id, None)   # süresi doldu, temizle
        return False
    return True

def _mark_exhausted(model_id: str, retry_after: float = 60.0):
    _exhausted[model_id] = time.time() + retry_after
```

429 yanıtında `retry-after` header'ı okunur (Groq saniye olarak verir; Gemini de `Retry-After` verir). Header yoksa varsayılan 60s kullanılır. Process restart'ta dict temizlenir — sorun değil, 429 yeniden öğretir. Redis gerekmez.

### Fully autonomous model registry

Hiçbir manuel işlem yok: manuel config düzenleme, tercih listesi tutma, elle tetikleme. Sistem startup'ta kendi model listesini üretir ve 24h'de bir günceller.

**Her node kendi registry'sini tutar — aynı kod, IP-aware davranış.**

`llm_service.py` hem node1'de hem node2'de çalışır. Kod hangi node olduğunu bilmez; Gemini validation probe IP'yi dolaylı olarak tespit eder:

| | node2 (US IP) | node1 (EU IP, fallback) |
|---|---|---|
| Groq discovery | ✅ 14 model | ✅ 14 model |
| Gemini probe | ✅ 200/429 → registry'e girer | ❌ 403 → registry'e girmez |
| Registry içeriği | Groq + Gemini | Sadece Groq |

**Sonuç:** node2 ayaktayken node1 isteği node2'ye iletir (Groq + Gemini zinciri). node2 düşünce node1 kendi Groq-only registry'sine düşer — fallback anında, sıfır gecikme, sıfır config değişikliği.

**Adım 1 — Listele:**
- Groq: `GET /openai/v1/models` → free key doğal filtredir, sadece erişilebilir modeller döner.
- Gemini: `GET /v1beta/models` → `supportedGenerationMethods` içinde `generateContent` olanları al; embedding/vision modelleri çıkar.

**Adım 2 — Validate (sadece Gemini):**
Groq'ta free key zaten filtre. Gemini'de model listesi paid/free için aynı döner; gerçekte free tier'da hangi modelin çalıştığı belli değil. Bu yüzden her Gemini model adayına startup'ta `"Say: ok"`, `max_tokens=1` ile minimal bir çağrı yapılır:
- `200` → aktif listeye al
- `429` → aktif listeye al (erişilebilir, kota dolmuş — aynı şey)
- `403 / 404` → çıkar (bu key ile kullanılamaz)

Bu adım tek seferlik, startup'ta yapılır. Gemini text generation modellerinin sayısı ~10–15 civarında; toplam maliyet ihmal edilebilir.

**Adım 3 — Otomatik sırala (heuristic):**
Manuel tercih listesi yok. Model adından çıkarılan sinyal puanlama:

```python
def _groq_score(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    # Aile önceliği
    if "gpt" in name:               score += 1000
    elif "qwen" in name:             score += 800
    elif "compound" in name:
        score += 400 if "mini" not in name else 200
    # Parametre sayısı (büyük = iyi)
    m = re.search(r'(\d+)b', name)
    if m: score += int(m.group(1))
    return score

def _gemini_score(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    # Tür önceliği (gemma en sona — TPM kısıtlı)
    if "gemma" in name:             score += 100
    elif "flash-lite" in name:      score += 500
    elif "flash" in name:           score += 400
    # Versiyon (3.5 > 3.1 > 2.0)
    m = re.search(r'(\d+)[.\-](\d+)', name)
    if m: score += float(f"{m.group(1)}.{m.group(2)}") * 50
    return score
```

**Adım 4 — Registry:**
```python
@dataclass
class _ModelRegistry:
    groq: list[str]    # sıralı, aktif modeller
    gemini: list[str]  # sıralı, validate edilmiş + aktif
    updated_at: float  # epoch

_registry: _ModelRegistry | None = None
```

Startup'ta doldurulur. 24h background task tekrar çalıştırır (`asyncio.create_task` + `asyncio.sleep(86400)` loop). Process restart'ta yeniden başlar — JSON cache'e gerek yok, startup süresi zaten birkaç saniye.

### 7.1 `llm_service.py` — Yeniden yazılır (non-streaming, fully autonomous)

```python
# _get_text_groq(system, user, model) → str   (stream=False, 429 → RateLimitError)
# _get_text_gemini(system, user, model) → str  (generateContent, 429 → RateLimitError)

import re, time, asyncio
from dataclasses import dataclass, field

# --- Exhaustion tracking ---
_exhausted: dict[str, float] = {}   # {model_id: reset_epoch}

def _is_exhausted(model_id: str) -> bool:
    ts = _exhausted.get(model_id)
    if ts is None: return False
    if time.time() >= ts:
        _exhausted.pop(model_id, None)
        return False
    return True

def _mark_exhausted(model_id: str, retry_after: float = 60.0):
    _exhausted[model_id] = time.time() + retry_after

def _parse_retry_after(exc) -> float:
    # Groq ve Gemini 'retry-after' header'ını RateLimitError içinde taşır
    try: return float(exc.response.headers.get("retry-after", 60))
    except Exception: return 60.0

# --- Model registry ---
@dataclass
class _ModelRegistry:
    groq: list[str] = field(default_factory=list)
    gemini: list[str] = field(default_factory=list)
    updated_at: float = 0.0

_registry = _ModelRegistry()

def _groq_score(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    if "gpt" in name:          score += 1000
    elif "qwen" in name:       score += 800
    elif "compound" in name:   score += 400 if "mini" not in name else 200
    m = re.search(r'(\d+)b', name)
    if m: score += int(m.group(1))
    return score

def _gemini_score(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    if "gemma" in name:           score += 100      # son çare (TPM kısıtlı)
    elif "flash-lite" in name:    score += 500
    elif "flash" in name:         score += 400
    m = re.search(r'(\d+)[.\-](\d+)', name)
    if m: score += float(f"{m.group(1)}.{m.group(2)}") * 50
    return score

async def _fetch_groq_models() -> list[str]:
    # GET /openai/v1/models — free key kendi filtresidir
    resp = await groq_client.models.list()
    ids = [m.id for m in resp.data]
    return sorted(ids, key=_groq_score, reverse=True)

async def _validate_gemini_model(model_id: str) -> bool:
    # 1-token probe: 200 veya 429 → erişilebilir; 403/404 → çıkar
    try:
        await _get_text_gemini("Reply: ok", "ok", model_id, max_tokens=1)
        return True
    except RateLimitError:
        return True   # 429 = erişilebilir, kota dolmuş
    except Exception:
        return False  # 403/404/ağ hatası → listeden çıkar

async def _fetch_gemini_models() -> list[str]:
    # GET /v1beta/models → generateContent destekleyenler → validate → sırala
    resp = await gemini_client.get(
        "https://generativelanguage.googleapis.com/v1beta/models",
        params={"key": settings.gemini_api_key}
    )
    candidates = [
        m["name"].removeprefix("models/")
        for m in resp.json().get("models", [])
        if "generateContent" in m.get("supportedGenerationMethods", [])
        and "embedding" not in m["name"].lower()
    ]
    # Paralel validate (rate limit olmadığı için hızlı)
    results = await asyncio.gather(*[_validate_gemini_model(m) for m in candidates])
    valid = [m for m, ok in zip(candidates, results) if ok]
    return sorted(valid, key=_gemini_score, reverse=True)

async def _refresh_registry():
    _registry.groq = await _fetch_groq_models()
    _registry.gemini = await _fetch_gemini_models()
    _registry.updated_at = time.time()
    logger.info("[AI] Registry güncellendi: groq=%d gemini=%d",
                len(_registry.groq), len(_registry.gemini))

async def start_registry_loop():
    """
    FastAPI lifespan'da çağrılır — hem main.py (node1) hem ai_proxy_main.py (node2).
    Aynı kod; Gemini probe sonucu IP'ye göre farklılaşır:
      node2: Groq + Gemini  |  node1: sadece Groq
    """
    await _refresh_registry()
    async def _loop():
        while True:
            await asyncio.sleep(86400)   # 24h
            await _refresh_registry()
    asyncio.create_task(_loop())

# --- Ana fonksiyon ---
async def generate_listing_description(title, category, ...) -> tuple[str, str]:
    system, user = _build_prompt(...)

    for model_id in _registry.groq:
        if _is_exhausted(model_id): continue
        try:
            raw = await _get_text_groq(system, user, model_id)
            return _post_process(raw, price), "groq"
        except RateLimitError as e:
            _mark_exhausted(model_id, _parse_retry_after(e)); continue
        except Exception: continue

    for model_id in _registry.gemini:
        if _is_exhausted(model_id): continue
        try:
            raw = await _get_text_gemini(system, user, model_id)
            return _post_process(raw, price), "gemini"
        except RateLimitError as e:
            _mark_exhausted(model_id, _parse_retry_after(e)); continue
        except Exception: continue

    return "", "error"
```

### 7.2 `ai_proxy_main.py` (node2'de çalışır)

```python
# backend/app/ai_proxy_main.py
# Çalıştırma: uvicorn app.ai_proxy_main:app --host 10.10.0.3 --port 8080

@app.post("/generate")
async def generate(body: GenerateRequest, x_internal_token: str = Header(...)):
    if x_internal_token != settings.node2_internal_token:
        raise HTTPException(status_code=403)
    text, provider = await generate_listing_description(**body.model_dump())
    if provider == "error":
        raise HTTPException(status_code=503)
    return {"text": text, "provider": provider}

@app.get("/health")
async def health():
    return {"status": "ok"}
```

### 7.3 `ai_proxy_client.py` (node1'de çalışır)

```python
async def generate_via_node2(params: dict) -> tuple[str, str]:
    """(text, provider) döndürür. node2 down → lokal fallback."""
    if settings.node2_ai_proxy_url:
        try:
            async with asyncio.timeout(45):
                r = await client.post(f"{settings.node2_ai_proxy_url}/generate",
                                      json=params,
                                      headers={"X-Internal-Token": settings.node2_internal_token})
                r.raise_for_status()
                data = r.json()
                return data["text"], data["provider"]
        except Exception as exc:
            logger.warning("[AI-PROXY] node2 başarısız, lokal fallback: %s", exc)

    # Lokal fallback (Groq only, EU IP — Gemini/Gemma EU'da çalışmaz)
    return await generate_listing_description(**params)
```

### 7.4 `listings.py` — SSE → JSON (node1)

```python
@router.post("/generate-description")
async def generate_description(body: GenerateDescriptionRequest, ...):
    # kredi kontrolü — mevcut mantık korunur
    ...
    text, provider = await generate_via_node2(params)
    if provider == "error":
        raise HTTPException(status_code=503)
    # kredi düş (başarılı yanıt sonrası)
    ...
    return {"description": text, "provider": provider, "tuci_spent": tuci_spent}
```

### 7.5 Mobile (`create_listing_screen.dart`)

```dart
// SSE streaming handler → düz HTTP POST
final resp = await http.post(uri, headers: headers, body: jsonEncode(params))
    .timeout(const Duration(seconds: 60));

if (resp.statusCode == 200) {
  final data = jsonDecode(resp.body);
  final fullText = data['description'] as String;
  final provider = data['provider'] as String;

  if (provider == 'gemini') {
    TeqSnackBar.show(message: loc.t('aiDescFallbackNotice'), ...);
  }

  // Client-side typewriter animasyonu
  for (int i = 0; i <= fullText.length; i++) {
    if (!mounted) break;
    setState(() => _descCtrl.text = fullText.substring(0, i));
    await Future.delayed(const Duration(milliseconds: 18));
  }
  _appendLocationSuffix();

  // Kredi UI güncelle
  final tuciSpent = (data['tuci_spent'] as num?)?.toInt() ?? 0;
  if (tuciSpent > 0) { ... }
}
```

---

## 8. Deploy Workflow (V1.2)

### node2 — İlk Kurulum (bir kez)

```bash
# 1. WireGuard
apt install -y wireguard
wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key
# → public key'i node1 ve gateway peer'larına ekle

# 2. WireGuard başlat
cp deploy/scale/V1.2/wireguard/node2-wg0.conf /etc/wireguard/wg0.conf
# (private key ve peer public key'leri doldur)
systemctl enable --now wg-quick@wg0

# 3. Repo
git clone https://github.com/tucibeyin/teqlif.git /var/www/teqlif.com
# .env oluştur (GROQ_API_KEY, GEMINI_API_KEY, NODE2_INTERNAL_TOKEN + dummy DB değerleri)

# 4. Python ortamı
cd /var/www/teqlif.com/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 5. Servisler
cp deploy/scale/V1.2/node2/systemd/teqlif-ai-proxy.service /etc/systemd/system/
cp deploy/scale/V1.2/node2/systemd/node_exporter.service   /etc/systemd/system/
cp deploy/scale/V1.2/node2/systemd/promtail.service         /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now teqlif-ai-proxy node_exporter promtail

# 6. UFW
ufw allow ssh && ufw allow 51820/udp
ufw allow from 10.10.0.1 to any port 8080
ufw allow from 10.10.0.2 to any port 9100
ufw enable
```

### node1 — WireGuard güncelleme

```bash
# wg0.conf'a node2 peer ekle (wg addpeer ile canlı veya restart ile)
sudo wg set wg0 peer <NODE2_PUBLIC_KEY> allowed-ips 10.10.0.3/32
sudo wg-quick save wg0
```

### node1 — Backend deploy

```bash
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif teqlif-staging
```

### gateway — WireGuard + Prometheus güncelleme

```bash
cd /var/www/teqlif.com && git pull
# wg0.conf'a node2 peer ekle
sudo wg set wg0 peer <NODE2_PUBLIC_KEY> allowed-ips 10.10.0.3/32 endpoint <NODE2_IP>:51820 persistent-keepalive 25
sudo wg-quick save wg0
# Prometheus güncelle
sudo cp deploy/scale/V1.2/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus
# UFW Loki push için
sudo ufw allow from 10.10.0.3 to any port 3100
```

---

## 9. Rollback Planı

| Senaryo | Aksiyon |
|---|---|
| node2 down | Otomatik — lokal fallback devreye girer (Groq only, EU IP) |
| node2 lokal fallback da başarısız | `503 AI service unavailable` — feature geçici kapalı |
| node2 WireGuard bozulur | `wg-quick down wg0` node2'de; lokal fallback aktif |
| Backend kodu sorunlu | `git revert` + `systemctl restart teqlif` |
| V1.1'e dönüş | node1/gateway WireGuard'dan node2 peer kaldır; eski listings.py SSE endpoint'ine dön |

---

## 10. Test Planı

```bash
# 1. WireGuard bağlantısı
ping 10.10.0.3          # node1'den veya gateway'den
ping 10.10.0.1          # node2'den

# 2. AI proxy sağlık
curl -s http://10.10.0.3:8080/health    # node1'den

# 3. AI proxy tam test
curl -s http://10.10.0.3:8080/generate \
  -H "X-Internal-Token: TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"iPhone 13","category":"telefon","condition":"used"}' \
  | python3 -m json.tool

# 4. Gemini erişim doğrulama (node2'den)
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=KEY" \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('models',[])))"
# Beklenen: 52

# 5. Production endpoint testi (gateway üzerinden)
curl -s -X POST https://teqlif.com/api/listings/generate-description \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"iPhone 13","category":"telefon","condition":"used"}'
# Beklenen: {"description": "...tam metin..."}

# 6. Fallback testi (node2 servisini durdur)
sudo systemctl stop teqlif-ai-proxy    # node2'de
# node1'den production endpoint'i tekrar çağır → lokal fallback çalışmalı
sudo systemctl start teqlif-ai-proxy   # node2'de
```

---

## 11. Kararlaşan Tasarım Noktaları

| Konu | Karar |
|---|---|
| node2 `.env` stratejisi | Mevcut şablona `NODE2_INTERNAL_TOKEN` eklenir; `DATABASE_URL`/`SECRET_KEY` placeholder kalır (import için gerekli, kullanılmaz) |
| Mobile SSE → JSON | Flutter `ai_proxy_client`'a POST → tam metin JSON; sonra client-side typewriter animasyonu |
| Typing animasyonu | Flutter sabit ~18ms/karakter hızında animasyon; "tap to skip" eklenebilir |
| Gemma 4 | Zincire eklenir, **son sırada** (son çare); TPM=16K → etkin ~18 RPM |
| Mono repo | Aynı git repo; node2 `ai_proxy_main.py`'ı, node1 `main.py`'ı çalıştırır |
| Fallback | `ai_proxy_client.py` → try node2, except → lokal `generate_listing_description()` |
| NODE2_INTERNAL_TOKEN | Deploy sırasında `openssl rand -hex 32` ile üretilir; her iki `.env`'e elle eklenir |
| In-memory exhaustion tracking | `_exhausted: dict[str, float]` — 429'da model_id → reset_epoch kaydedilir; sonraki request atlar; process restart'ta temizlenir |
| Fully autonomous registry | Startup + 24h refresh; Groq: API key filtresi + heuristic sıralama; Gemini: generateContent filtre → 1-token probe ile validate → heuristic sıralama; sıfır manuel config |
| Gemini validation probe | Her Gemini modeline startup'ta `max_tokens=1` çağrı: 200/429 → aktif listeye al, 403/404 → çıkar |
| Registry her node'da ayrı | node1 ve node2 bağımsız registry; aynı kod, Gemini probe IP'yi dolaylı tespit eder |
| GROQ/GEMINI_MODEL_PREFERENCE | Kaldırıldı — sıralama tamamen heuristic ile yapılır, env var gerekmez |
