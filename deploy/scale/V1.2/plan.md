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
1. Groq openai/gpt-oss-120b  →  1.000 RPD
2. Groq openai/gpt-oss-20b   →  1.000 RPD
3. Groq qwen/qwen3.6-27b     →  1.000 RPD
4. Groq qwen/qwen3.8-27b     →  1.000 RPD
5. Groq groq/compound         →    250 RPD
6. Groq groq/compound-mini    →    250 RPD
                               ─────────────
   Groq toplam                → ~4.500 RPD
                               ─────────────
7. Gemini 3.5 Flash Lite      →    500 RPD  ← EU'dan erişilemeyen, şimdi çalışır
8. Gemini 3.1 Flash Lite      →    500 RPD  ← mevcut kodda var, ikinci sıra
                               ─────────────
   Genel toplam               → ~5.500 RPD/gün
```

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
| Streaming → Tam metin | **Tam metin JSON** | ARQ veya proxy, her ikisi de streaming kırar; kullanıcı zaten bekliyor |
| Proxy vs ARQ | **HTTP Proxy** | Stateless; node2 Redis/DB'ye erişmez; fallback trivial |
| Kredi düşme zamanı | **Başarılı yanıt sonrası** | Yarım/hatalı yanıt için ücret alınmaz |
| Fallback | **node2 down → node1 lokal çağrı** | Groq EU'dan çalışır (düşük kota ama funcitonal) |
| Auth | **X-Internal-Token header** | WireGuard şifreleme + shared secret: çift katman |
| node2 servis portu | **10.10.0.3:8080** (WireGuard IP'de) | Kamuya açık port yok |
| node2 kod temeli | **Mevcut repo** (git pull) | `llm_service.py` yeniden kullanılır |

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

### 7.1 `ai_proxy_main.py` (node2'de çalışır)

```python
# backend/app/ai_proxy_main.py
# Çalıştırma: uvicorn app.ai_proxy_main:app --host 10.10.0.3 --port 8080

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from app.services.ml.llm_service import generate_listing_description
from app.config import settings  # GROQ_API_KEY, GEMINI_API_KEY, node2_internal_token

app = FastAPI(docs_url=None, redoc_url=None)  # public UI yok

class GenerateRequest(BaseModel):
    title: str
    category: str
    condition: str | None = None
    price: float | None = None
    subcategory: str | None = None
    extra_fields: dict | None = None
    lang: str = "tr"

@app.post("/generate")
async def generate(body: GenerateRequest, x_internal_token: str = Header(...)):
    if x_internal_token != settings.node2_internal_token:
        raise HTTPException(status_code=403)
    text = await generate_listing_description(**body.model_dump())
    if text == "__LLM_ERROR__":
        raise HTTPException(status_code=503, detail="LLM chain failed")
    return {"text": text}

@app.get("/health")
async def health():
    return {"status": "ok"}
```

### 7.2 `llm_service.py` — Non-streaming wrapper (node2 + lokal fallback için)

```python
# llm_service.py'ye eklenecek
async def generate_listing_description(
    title: str,
    category: str,
    condition: str | None = None,
    price: float | None = None,
    subcategory: str | None = None,
    extra_fields: dict | None = None,
    lang: str = "tr",
) -> str:
    """Tam metin döndürür. generate_listing_description_stream'i collect eder."""
    chunks = []
    async for chunk in generate_listing_description_stream(
        title, category, condition, price, subcategory, extra_fields, lang
    ):
        if chunk.startswith("__META_"):
            continue
        if chunk == "__LLM_ERROR__":
            return "__LLM_ERROR__"
        chunks.append(chunk)
    return "".join(chunks)
```

### 7.3 `ai_proxy_client.py` (node1'de çalışır)

```python
# backend/app/services/ml/ai_proxy_client.py
import asyncio, logging, httpx
from app.config import settings
from app.services.ml.llm_service import generate_listing_description

logger = logging.getLogger(__name__)

async def generate_via_node2(params: dict) -> str:
    """node2 AI proxy → lokal fallback."""
    try:
        async with asyncio.timeout(45):
            async with httpx.AsyncClient() as client:
                r = await client.post(
                    f"{settings.node2_ai_proxy_url}/generate",
                    json=params,
                    headers={"X-Internal-Token": settings.node2_internal_token},
                    timeout=44.0,
                )
                r.raise_for_status()
                return r.json()["text"]
    except Exception as exc:
        logger.warning("[AI-PROXY] node2 başarısız, lokal fallback: %s", exc)

    # Lokal fallback (Groq only, EU IP — Gemini çalışmaz)
    return await generate_listing_description(**params)
```

### 7.4 `listings.py` — SSE → JSON (node1)

```python
# Mevcut SSE endpoint (EventSourceResponse) → normal JSON endpoint
@router.post("/generate-description")
async def generate_description(body: GenerateDescriptionRequest, ...):
    # kredi kontrolü (mevcut mantık korunur)
    ...
    params = body.model_dump(exclude={"session_token"})
    text = await generate_via_node2(params)
    if text == "__LLM_ERROR__":
        raise HTTPException(status_code=503)
    # kredi düş (başarılı yanıt sonrası)
    ...
    return {"description": text}
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

## 11. Açık Sorular (Uygulama Öncesi Karar Gerekiyor)

- [ ] **node2 `.env` stratejisi:** `ai_proxy_main.py` mevcut `app.config.settings`'i import ederse tüm zorunlu config alanları (DATABASE_URL, SECRET_KEY vb.) node2'nin `.env`'inde de olmalı — dummy değerlerle mi, yoksa `ai_proxy_config.py` ayrı minimal config mi?
- [ ] **Mobile SSE → JSON değişikliği:** Flutter tarafındaki `generate_description` akışı nasıl güncellenir? (Şu an SSE stream handler var)
- [ ] **Gemma 4 (26B / 31B) Gemini chain'e eklenecek mi?** 14.400 RPD ile en yüksek kota; önce kalite testi gerekli.
- [ ] **NODE2_INTERNAL_TOKEN değeri:** Üretilip `.env` ve node2'nin `.env`'ine elle yazılacak.
