# Teqlif Scale V1.2 — Task Log

> **Baseline:** V1.1 aktif (2026-09-10).  
> **Hedef:** node2 AI proxy ayağa kaldır, node1 SSE → JSON geçişi, Flutter typewriter animasyonu.  
> **node2 mevcut durum:** Repo klonlandı, başka hiçbir şey yok.  
> **Kural:** Her adım bitmeden sonraki başlamaz. VPS adımları kullanıcı çalıştırır, çıktıyı paylaşır.

---

## Faz 1 — Kod Değişiklikleri (Yerel → Git Push)

### Görev 1 — `config.py`: node2 alanları ekle

**Durum:** [ ]

**Dosya:** `backend/app/config.py`

`gemini_api_key` satırının hemen altına ekle:

```python
node2_ai_proxy_url: str = ""       # ör. "http://10.10.0.3:8080" — boşsa lokal fallback
node2_internal_token: str = ""     # openssl rand -hex 32 ile üretilir
```

**Doğrulama:** `python3 -c "from app.config import settings; print(settings.node2_ai_proxy_url)"` → boş string döner.

---

### Görev 2 — `exceptions.py`: `AIServiceBusyException` ✅

**Durum:** [x] — Tamamlandı (önceki oturumda eklendi)

`backend/app/core/exceptions.py` sonuna eklendi:
```python
class AIServiceBusyException(AppException):
    """503 — Tüm AI modelleri kota dolduğundan veya erişilemez."""
    def __init__(self, message: str | None = None):
        super().__init__(status_code=503, message=message, code="AI_SERVICE_BUSY")
```

---

### Görev 3 — `llm_service.py`: Tamamen yeniden yaz

**Durum:** [ ]

**Dosya:** `backend/app/services/ml/llm_service.py`

Kaldırılacaklar: `generate_listing_description_stream`, `_tokens_groq`, `_tokens_gemini`, `_sentence_stream`, `_quota_ok`, sentinel token'lar (`__META_groq__` vb.), `_GROQ_MODELS` hardcode list, `_GEMINI_DAILY_LIMIT`.

Korunacaklar: `_build_prompt`, `_build_suffix`, `_RE_AI_OPENER`, `_CAT_NORMALIZE`, `_CONDITION_LABELS`, `llm_templates.py` import'ları — bunlara dokunma.

Eklenecekler (plan.md §7.1'deki tam tasarım):

```python
import re, time, asyncio, logging
from dataclasses import dataclass, field
from app.core.logger import get_logger, fire_and_forget

logger = get_logger(__name__)

# ── Exhaustion tracking ────────────────────────────────────────────────────────
_exhausted: dict[str, float] = {}

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
    try: return float(exc.response.headers.get("retry-after", 60))
    except Exception: return 60.0

# ── Model registry ─────────────────────────────────────────────────────────────
@dataclass
class _ModelRegistry:
    groq: list[str] = field(default_factory=list)
    gemini: list[str] = field(default_factory=list)
    updated_at: float = 0.0

_registry = _ModelRegistry()

def _groq_score(model_id: str) -> float:
    name = model_id.lower(); score = 0.0
    if "gpt" in name:        score += 1000
    elif "qwen" in name:     score += 800
    elif "compound" in name: score += 400 if "mini" not in name else 200
    m = re.search(r'(\d+)b', name)
    if m: score += int(m.group(1))
    return score

def _gemini_score(model_id: str) -> float:
    name = model_id.lower(); score = 0.0
    if "gemma" in name:          score += 100
    elif "flash-lite" in name:   score += 500
    elif "flash" in name:        score += 400
    m = re.search(r'(\d+)[.\-](\d+)', name)
    if m: score += float(f"{m.group(1)}.{m.group(2)}") * 50
    return score

async def _fetch_groq_models() -> list[str]:
    resp = await groq_client.models.list()
    ids = [m.id for m in resp.data]
    return sorted(ids, key=_groq_score, reverse=True)

async def _validate_gemini_model(model_id: str) -> bool:
    try:
        await _get_text_gemini("Reply: ok", "ok", model_id, max_tokens=1)
        return True
    except RateLimitError:
        return True
    except Exception:
        return False

async def _fetch_gemini_models() -> list[str]:
    resp = await gemini_http_client.get(
        "https://generativelanguage.googleapis.com/v1beta/models",
        params={"key": settings.gemini_api_key}
    )
    candidates = [
        m["name"].removeprefix("models/")
        for m in resp.json().get("models", [])
        if "generateContent" in m.get("supportedGenerationMethods", [])
        and "embedding" not in m["name"].lower()
    ]
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
    Gemini probe IP'ye göre otomatik farklılaşır: node2=Groq+Gemini, node1=sadece Groq.
    """
    try:
        await _refresh_registry()
    except Exception as exc:
        logger.error("[AI] Registry startup başarısız, boş registry ile devam: %s", exc)

    async def _loop():
        while True:
            await asyncio.sleep(86400)
            try:
                await _refresh_registry()
            except Exception as exc:
                logger.warning("[AI] Registry 24h refresh başarısız: %s", exc)

    fire_and_forget(_loop(), tag="llm_service.registry_loop")

# ── Ana fonksiyon ──────────────────────────────────────────────────────────────
async def generate_listing_description(title, category, condition=None,
                                        price=None, subcategory=None,
                                        extra_fields=None, lang="tr") -> tuple[str, str]:
    system, user = _build_prompt(title, category, condition, price,
                                  subcategory, extra_fields, lang)

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

`_get_text_groq` ve `_get_text_gemini` — mevcut stream versiyonlarından uyarlanır: `stream=False`, tam metin string döner.  
`_post_process(raw, price)` — mevcut `_RE_AI_OPENER` temizleme + `_build_suffix` uygulaması (stream'de chunk'lara uygulananları full string'e taşı).

**Doğrulama:** `python3 -c "from app.services.ml.llm_service import generate_listing_description"` — import hatası olmamalı.

---

### Görev 4 — `ai_proxy_client.py`: Yeni dosya

**Durum:** [ ]

**Dosya:** `backend/app/services/ml/ai_proxy_client.py` (yeni)

```python
import asyncio
import httpx
from app.config import settings
from app.core.logger import get_logger
from app.services.ml.llm_service import generate_listing_description

logger = get_logger(__name__)
_client = httpx.AsyncClient(timeout=None)   # timeout asyncio.timeout ile yönetilir


async def generate_via_node2(params: dict) -> tuple[str, str]:
    """(text, provider) döner. node2 down veya boşsa → lokal Groq-only fallback."""
    if settings.node2_ai_proxy_url:
        try:
            async with asyncio.timeout(45):
                r = await _client.post(
                    f"{settings.node2_ai_proxy_url}/generate",
                    json=params,
                    headers={"X-Internal-Token": settings.node2_internal_token},
                )
                r.raise_for_status()
                data = r.json()
                return data["text"], data["provider"]
        except Exception as exc:
            logger.warning("[AI-PROXY] node2 başarısız, lokal fallback: %s", exc)

    return await generate_listing_description(**params)
```

---

### Görev 5 — `ai_proxy_main.py`: Yeni dosya

**Durum:** [ ]

**Dosya:** `backend/app/ai_proxy_main.py` (yeni)

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from app.config import settings
from app.services.ml.llm_service import generate_listing_description, start_registry_loop
from app.logging_config import setup_logging

logger = setup_logging()


class GenerateRequest(BaseModel):
    title: str
    category: str
    condition: str | None = None
    price: float | None = None
    subcategory: str | None = None
    extra_fields: dict | None = None
    lang: str = "tr"


@asynccontextmanager
async def lifespan(app: FastAPI):
    await start_registry_loop()
    yield


app = FastAPI(lifespan=lifespan)


@app.post("/generate")
async def generate(body: GenerateRequest, x_internal_token: str = Header(...)):
    if x_internal_token != settings.node2_internal_token:
        raise HTTPException(status_code=403)
    description, provider = await generate_listing_description(**body.model_dump())
    if provider == "error":
        raise HTTPException(status_code=503)
    return {"text": description, "provider": provider}


@app.get("/health")
async def health():
    return {"status": "ok"}
```

**Not:** node2'de DB/Redis/LiveKit/MinIO import yok — yalnızca `llm_service` + `config` + `logging_config`.

---

### Görev 6 — `listings.py`: SSE → JSON

**Durum:** [ ]

**Dosya:** `backend/app/routers/listings.py` (satır 684–806 arası)

**Kaldır:**
- `StreamingResponse` import'u
- `event_generator()` async generator fonksiyonu
- `generate_listing_description_stream` import'u

**Ekle:**
```python
from app.services.ml.ai_proxy_client import generate_via_node2
from app.core.exceptions import AIServiceBusyException
```

**Endpoint'i değiştir** (satır 684 civarı `@router.post("/generate-description")`):

```python
@router.post("/generate-description")
@limiter.limit("10/minute")
async def generate_description(
    request: Request,
    body: GenerateDescriptionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # ── Kredi ön kontrolü (mevcut mantık korunur) ──────────────────────────────
    _ai_desc_cost  = credit_service.cost_tuci("ai_desc")
    _ai_desc_limit = credit_service.free_limit("ai_desc", is_premium=True)
    if current_user.is_premium:
        ai_used = await credit_service.get_used("ai_desc", current_user.id, current_user.premium_since)
        if ai_used >= _ai_desc_limit and current_user.tuci_balance < _ai_desc_cost:
            raise InsufficientFundsException(code="MONTHLY_LIMIT_INSUFFICIENT_FUNDS")
    else:
        if current_user.tuci_balance < _ai_desc_cost:
            raise InsufficientFundsException()

    # ── AI üretimi ─────────────────────────────────────────────────────────────
    params = dict(
        title=body.title, category=body.category, condition=body.condition,
        price=body.price, subcategory=body.subcategory,
        extra_fields=body.extra_fields, lang=body.lang,
    )
    description, provider = await generate_via_node2(params)
    if provider == "error":
        raise AIServiceBusyException()

    # ── Kredi düş (başarılı yanıt sonrası) ────────────────────────────────────
    tuci_spent = 0
    try:
        if current_user.is_premium:
            ai_used_new = await credit_service.increment("ai_desc", current_user.id, current_user.premium_since)
            if ai_used_new > _ai_desc_limit:
                await db.execute(
                    sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                    {"cost": _ai_desc_cost, "uid": current_user.id},
                )
                db.add(TuciTransaction(user_id=current_user.id, amount=-_ai_desc_cost,
                                       transaction_type="spend_ai_desc"))
                await db.commit()
                tuci_spent = _ai_desc_cost
        else:
            await db.execute(
                sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                {"cost": _ai_desc_cost, "uid": current_user.id},
            )
            db.add(TuciTransaction(user_id=current_user.id, amount=-_ai_desc_cost,
                                   transaction_type="spend_ai_desc"))
            await db.commit()
            tuci_spent = _ai_desc_cost
    except Exception as e:
        logger.error("[AI Desc] Kredi sayma başarısız: %s", e)

    return {"description": description, "provider": provider, "tuci_spent": tuci_spent}
```

**Not:** SQLAlchemy `text()` import'u `sql_text` alias'ına alınır — `from sqlalchemy import text as sql_text` — `description` değişken ismiyle çakışmayı önlemek için.

---

### Görev 7 — `main.py`: Lifespan'a registry başlatma ekle

**Durum:** [ ]

**Dosya:** `backend/main.py`

Lifespan'da `hype_manager.start_decay()` satırından önce şunu ekle:

```python
# node1 kendi Groq-only registry'sini kurar (EU IP, Gemini probe → 403 → listeden çıkar)
from app.services.ml.llm_service import start_registry_loop as _start_ai_registry
await _start_ai_registry()
```

**Doğrulama:** Servis restart'ta log'da `[AI] Registry güncellendi: groq=N gemini=0` görünmeli (node1, EU IP — Gemini yok).

---

### Görev 8 — ARB dosyaları: `aiDescFallbackNotice` ekle

**Durum:** [ ]

**Dosyalar:** `mobile/lib/l10n/` altındaki 4 ARB dosyası

```json
// app_tr.arb
"aiDescFallbackNotice": "Açıklama yedek model ile üretildi.",

// app_en.arb
"aiDescFallbackNotice": "Description generated with a fallback model.",

// app_ar.arb
"aiDescFallbackNotice": "تم إنشاء الوصف باستخدام نموذج بديل.",

// app_ru.arb
"aiDescFallbackNotice": "Описание создано с использованием резервной модели.",
```

**Not:** `AI_SERVICE_BUSY` hata kodu `ErrorMapper`'da zaten tanımlı — backend AppException olarak döneceği için yeni ARB key gerekmez.

---

### Görev 9 — Flutter: `create_listing_screen.dart` SSE → JSON + AiDescNotifier

**Durum:** [ ]

**9.1 — `AiDescNotifier` oluştur**

**Dosya:** `mobile/lib/viewmodels/create_listing/ai_desc_notifier.dart` (yeni)

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:teqlif/core/error_helper.dart';
import 'package:teqlif/services/api_service.dart';
import 'package:teqlif/services/localization_service.dart';

part 'ai_desc_notifier.g.dart';

enum AiDescStatus { idle, loading, done, error }

class AiDescState {
  final AiDescStatus status;
  final String text;
  final String provider;
  final int tuciSpent;

  const AiDescState({
    this.status = AiDescStatus.idle,
    this.text = '',
    this.provider = '',
    this.tuciSpent = 0,
  });
}

@riverpod
class AiDescNotifier extends _$AiDescNotifier {
  @override
  AiDescState build() => const AiDescState();

  Future<void> generate(Map<String, dynamic> params) async {
    state = const AiDescState(status: AiDescStatus.loading);

    final result = await ApiService.instance.post<Map<String, dynamic>>(
      '/listings/generate-description',
      data: params,
    );

    result.when(
      ok: (data) {
        state = AiDescState(
          status: AiDescStatus.done,
          text: data['description'] as String,
          provider: data['provider'] as String,
          tuciSpent: (data['tuci_spent'] as num?)?.toInt() ?? 0,
        );
      },
      err: (error) {
        state = const AiDescState(status: AiDescStatus.error);
        handleError(error, ref.read(localizationProvider));
      },
    );
  }

  void reset() => state = const AiDescState();
}
```

**9.2 — `create_listing_screen.dart` güncelle**

- `ref.watch(aiDescNotifierProvider)` ile state izle
- SSE event generator kodunu tamamen kaldır
- `_isLoading` bool'u provider state'inden al (`status == AiDescStatus.loading`)
- `status == AiDescStatus.done` → typewriter animasyonunu başlat

```dart
// State izleme — build() içinde
final aiDesc = ref.watch(aiDescNotifierProvider);

// AI buton onPressed
onPressed: aiDesc.status == AiDescStatus.loading ? null : () {
  ref.read(aiDescNotifierProvider.notifier).generate({
    'title': _titleCtrl.text,
    'category': _category,
    'condition': _condition,
    'price': _price,
    'subcategory': _subcategory,
    'extra_fields': _extraValues,
    'lang': _lang,
  });
},
isLoading: aiDesc.status == AiDescStatus.loading,
```

**Typewriter + done state (ref.listen ile):**
```dart
ref.listen<AiDescState>(aiDescNotifierProvider, (prev, next) async {
  if (next.status != AiDescStatus.done) return;
  if (prev?.status == AiDescStatus.done) return;   // tekrar tetiklenme

  // Kredi UI hemen güncelle
  if (next.tuciSpent > 0) _updateTuciBalance(next.tuciSpent);
  if (next.provider == 'gemini') {
    TeqSnackBar.show(message: loc.t('aiDescFallbackNotice'));
  }

  // Typewriter
  _skipAnimation = false;
  final fullText = next.text;
  for (int i = 0; i <= fullText.length; i++) {
    if (!mounted || _skipAnimation) break;
    setState(() => _descCtrl.text = fullText.substring(0, i));
    await Future.delayed(const Duration(milliseconds: 18));
  }
  if (mounted) {
    setState(() => _descCtrl.text = fullText);
    _appendLocationSuffix();
  }
});
```

`_skipAnimation` screen-local kalır (saf UI davranışı):
```dart
bool _skipAnimation = false;

void _onTapDuringAnimation() {
  if (ref.read(aiDescNotifierProvider).status == AiDescStatus.loading) {
    _skipAnimation = true;
  }
}
```

**Doğrulama:** `dart analyze mobile/` → 0 hata. Cihazda test: AI butonu → loading → typewriter → kredi azalır. Tap sırasında → animasyon atlar, tam metin gösterilir.

---

### Görev 10 — Git commit + push

**Durum:** [ ]

```bash
cd /Users/tucibeyin/Desktop/teqlif
git add backend/app/config.py \
        backend/app/core/exceptions.py \
        backend/app/services/ml/llm_service.py \
        backend/app/services/ml/ai_proxy_client.py \
        backend/app/ai_proxy_main.py \
        backend/app/routers/listings.py \
        backend/main.py \
        mobile/lib/l10n/app_tr.arb \
        mobile/lib/l10n/app_en.arb \
        mobile/lib/l10n/app_ar.arb \
        mobile/lib/l10n/app_ru.arb \
        mobile/lib/viewmodels/create_listing/ai_desc_notifier.dart \
        mobile/lib/viewmodels/create_listing/ai_desc_notifier.g.dart \
        mobile/lib/screens/create_listing_screen.dart \
        deploy/scale/V1.2/
git commit -m "feat(ai): Scale V1.2 — node2 AI proxy, non-streaming registry, typewriter UI"
git push origin main
```

---

## Faz 2 — node2 Kurulum (Her adım için çıktı paylaş)

### Görev 11 — Python ortamı kur

**Durum:** [ ]

node2'de çalıştır:

```bash
cd /var/www/teqlif.com/backend
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
```

**Doğrulama:**
```bash
.venv/bin/python -c "import fastapi, groq, httpx; print('OK')"
```

---

### Görev 12 — `.env` dosyası oluştur

**Durum:** [ ]

node2'de `NODE2_INTERNAL_TOKEN` üret ve kaydet (aynı değer node1'e de eklenecek):

```bash
openssl rand -hex 32   # çıktıyı kopyala
```

Sonra `.env` oluştur:

```bash
cat > /var/www/teqlif.com/backend/.env << 'EOF'
DATABASE_URL=postgresql+asyncpg://placeholder:placeholder@localhost/placeholder
SECRET_KEY=placeholder_not_used_on_node2
GROQ_API_KEY=gsk_...          # gerçek değer
GEMINI_API_KEY=AIza...        # gerçek değer
NODE2_INTERNAL_TOKEN=...      # üretilen token
SENTRY_BACKEND_DSN=           # boş bırak — node2 hatalar Loki'ye gider
EOF
chmod 600 /var/www/teqlif.com/backend/.env
```

**Doğrulama:**
```bash
.venv/bin/python -c "from app.config import settings; print(settings.groq_api_key[:8])"
```

---

### Görev 13 — WireGuard kur + yapılandır

**Durum:** [ ]

```bash
apt install -y wireguard

# Key üret
wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key
chmod 600 /etc/wireguard/node2_private.key
cat /etc/wireguard/node2_public.key   # → node1 ve gateway'e eklenecek
```

Public key'i paylaş → node1 ve gateway peer'larına eklenecek (Görev 17–18).

`/etc/wireguard/wg0.conf` oluştur (plan §6.1'deki config — private key ve peer public key'leri doldur):

```bash
cp /var/www/teqlif.com/deploy/scale/V1.2/wireguard/node2-wg0.conf /etc/wireguard/wg0.conf
# Private key ve peer public key'leri düzenle:
nano /etc/wireguard/wg0.conf
```

```bash
systemctl enable --now wg-quick@wg0
wg show    # interface ve peer'lar görünmeli
```

**Not:** node1 ve gateway peer'ları eklenmeden handshake olmaz (Görev 17–18 sonrası test et).

---

### Görev 14 — UFW yapılandır

**Durum:** [ ]

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 51820/udp                              # WireGuard
ufw allow from 10.10.0.1 to any port 8080        # AI proxy ← node1
ufw allow from 10.10.0.2 to any port 9100        # node_exporter ← gateway Prometheus
ufw --force enable
ufw status
```

---

### Görev 15 — Log dizini (symlink)

**Durum:** [ ]

`logging_config.py` backend/logs/ klasörüne yazar; promtail /var/log/teqlif/ bekler:

```bash
mkdir -p /var/www/teqlif.com/backend/logs
sudo ln -sf /var/www/teqlif.com/backend/logs /var/log/teqlif
ls -la /var/log/teqlif   # → symlink görünmeli
```

---

### Görev 16 — node_exporter kur + başlat

**Durum:** [ ]

```bash
# İndir (son sürümü kontrol et: https://github.com/prometheus/node_exporter/releases)
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
sudo cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Servis dosyasını kopyala
sudo cp /var/www/teqlif.com/deploy/scale/V1.2/node2/systemd/node_exporter.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

**Doğrulama (WireGuard sonrası):**
```bash
curl -s http://10.10.0.3:9100/metrics | head -5
```

---

### Görev 17 — promtail kur + yapılandır + başlat

**Durum:** [ ]

```bash
# İndir (node1'deki sürümle eşleştir)
cd /tmp
wget https://github.com/grafana/loki/releases/download/v3.1.0/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo cp promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail

# Config ve servis dosyalarını kopyala
sudo cp /var/www/teqlif.com/deploy/scale/V1.2/node2/promtail-config.yml /etc/promtail-config.yml
sudo cp /var/www/teqlif.com/deploy/scale/V1.2/node2/systemd/promtail.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now promtail
```

**Doğrulama (WireGuard ve Loki bağlantısı sonrası):**
```bash
sudo systemctl status promtail   # active (running)
```

---

### Görev 18 — teqlif-ai-proxy servisi kur + başlat

**Durum:** [ ]

```bash
sudo cp /var/www/teqlif.com/deploy/scale/V1.2/node2/systemd/teqlif-ai-proxy.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now teqlif-ai-proxy
```

**Doğrulama:**
```bash
sudo systemctl status teqlif-ai-proxy   # active (running)
curl -s http://10.10.0.3:8080/health    # {"status": "ok"} — WireGuard sonrası node1'den
```

Log'da registry başlangıcını kontrol et:
```bash
journalctl -u teqlif-ai-proxy -n 30
# [AI] Registry güncellendi: groq=N gemini=M
```

---

## Faz 3 — node1 WireGuard + Backend Güncelleme

### Görev 19 — node1: WireGuard node2 peer ekle

**Durum:** [ ]

node2 public key'i (Görev 13'ten) node1'e ekle:

```bash
sudo wg set wg0 peer <NODE2_PUBLIC_KEY> allowed-ips 10.10.0.3/32
sudo wg-quick save wg0
```

**Doğrulama:**
```bash
ping -c 3 10.10.0.3   # node1'den node2'ye
```

---

### Görev 20 — node1: `.env` güncelle

**Durum:** [ ]

node1 `.env`'e şu satırları ekle:

```bash
NODE2_AI_PROXY_URL=http://10.10.0.3:8080
NODE2_INTERNAL_TOKEN=...   # Görev 12'de üretilen token (aynı değer)
```

---

### Görev 21 — node1: git pull + ARB sync + restart

**Durum:** [ ]

```bash
cd /var/www/teqlif.com
git pull
python3 scripts/sync_translations.py   # aiDescFallbackNotice DB'ye yazılır
sudo systemctl restart teqlif teqlif-staging
```

**Doğrulama:**
```bash
sudo systemctl status teqlif   # active (running)
journalctl -u teqlif -n 20
# [AI] Registry güncellendi: groq=N gemini=0  ← node1 EU IP, Gemini yok
```

---

## Faz 4 — gateway Güncellemesi

### Görev 22 — gateway: WireGuard node2 peer ekle

**Durum:** [ ]

node2 public key ve public IP'siyle (RackNerd panelinden öğren):

```bash
sudo wg set wg0 peer <NODE2_PUBLIC_KEY> \
    allowed-ips 10.10.0.3/32 \
    endpoint <NODE2_PUBLIC_IP>:51820 \
    persistent-keepalive 25
sudo wg-quick save wg0
```

**Doğrulama:**
```bash
ping -c 3 10.10.0.3   # gateway'den node2'ye
```

---

### Görev 23 — gateway: UFW Loki push izni

**Durum:** [ ]

```bash
sudo ufw allow from 10.10.0.3 to any port 3100
```

---

### Görev 24 — gateway: Prometheus güncelle + reload

**Durum:** [ ]

```bash
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.2/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp deploy/scale/V1.2/gateway/prometheus-rules.yml /etc/prometheus/rules/teqlif.yml
sudo systemctl restart prometheus
```

**Doğrulama:**
```bash
# Prometheus UI'da (http://10.10.0.2:9090) node-node2 target'ı UP görünmeli
curl -s http://10.10.0.2:9090/api/v1/targets | python3 -m json.tool | grep node2
```

---

## Faz 5 — Son Testler

### Görev 25 — WireGuard tam mesh doğrulama

**Durum:** [ ]

```bash
# node1'den
ping -c 3 10.10.0.3   # node2
ping -c 3 10.10.0.2   # gateway

# node2'den
ping -c 3 10.10.0.1   # node1
ping -c 3 10.10.0.2   # gateway

# gateway'den
ping -c 3 10.10.0.3   # node2
ping -c 3 10.10.0.1   # node1
```

---

### Görev 26 — AI proxy uçtan uca test

**Durum:** [ ]

```bash
# node1'den — AI proxy health
curl -s http://10.10.0.3:8080/health
# Beklenen: {"status":"ok"}

# node1'den — tam generate testi
curl -s -X POST http://10.10.0.3:8080/generate \
  -H "X-Internal-Token: <NODE2_INTERNAL_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"iPhone 13","category":"telefon","condition":"used","lang":"tr"}' \
  | python3 -m json.tool
# Beklenen: {"text": "...açıklama...", "provider": "groq" veya "gemini"}

# node2'den — Gemini erişim doğrula
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=<GEMINI_API_KEY>" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('models',[])))"
# Beklenen: 50+ model
```

---

### Görev 27 — Production endpoint testi

**Durum:** [ ]

```bash
curl -s -X POST https://teqlif.com/api/listings/generate-description \
  -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"iPhone 13","category":"telefon","condition":"used","lang":"tr"}'
# Beklenen: {"description": "...", "provider": "groq"|"gemini", "tuci_spent": N}
```

---

### Görev 28 — Fallback testi

**Durum:** [ ]

node2'de AI proxy'yi durdur, production'dan istek gönder:

```bash
# node2'de
sudo systemctl stop teqlif-ai-proxy

# node1'den (veya local curl ile)
curl -s -X POST https://teqlif.com/api/listings/generate-description \
  -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"iPhone 13","category":"telefon","condition":"used","lang":"tr"}'
# Beklenen: başarılı yanıt (lokal Groq fallback, provider="groq")

# node1 log'unda kontrol et
journalctl -u teqlif -n 10 | grep "AI-PROXY"
# [AI-PROXY] node2 başarısız, lokal fallback: ...

# node2'de tekrar başlat
sudo systemctl start teqlif-ai-proxy
```

---

### Görev 29 — Monitoring doğrulama

**Durum:** [ ]

```bash
# AIProxyDown alert aktif mi? (node2 servisi durduruluyken 1 dakika bekle)
# Prometheus UI → Alerts → AIProxyDown → firing görünmeli

# Loki'de node2 logları geliyor mu?
# Grafana → Explore → Loki → {node="node2"} → son satırlar görünmeli
```

---

## Özet — Tamamlanma Durumu

| Faz | Görev | Durum |
|---|---|---|
| Kod | 1 — config.py | [ ] |
| Kod | 2 — exceptions.py | [x] |
| Kod | 3 — llm_service.py | [ ] |
| Kod | 4 — ai_proxy_client.py | [ ] |
| Kod | 5 — ai_proxy_main.py | [ ] |
| Kod | 6 — listings.py | [ ] |
| Kod | 7 — main.py lifespan | [ ] |
| Kod | 8 — ARB dosyaları | [ ] |
| Kod | 9 — Flutter AiDescNotifier | [ ] |
| Kod | 10 — Git push | [ ] |
| node2 | 11 — Python ortamı | [ ] |
| node2 | 12 — .env | [ ] |
| node2 | 13 — WireGuard | [ ] |
| node2 | 14 — UFW | [ ] |
| node2 | 15 — Log symlink | [ ] |
| node2 | 16 — node_exporter | [ ] |
| node2 | 17 — promtail | [ ] |
| node2 | 18 — teqlif-ai-proxy servisi | [ ] |
| node1 | 19 — WireGuard peer | [ ] |
| node1 | 20 — .env güncelle | [ ] |
| node1 | 21 — git pull + restart | [ ] |
| gateway | 22 — WireGuard peer | [ ] |
| gateway | 23 — UFW Loki | [ ] |
| gateway | 24 — Prometheus + rules | [ ] |
| Test | 25 — WireGuard mesh | [ ] |
| Test | 26 — AI proxy uçtan uca | [ ] |
| Test | 27 — Production endpoint | [ ] |
| Test | 28 — Fallback | [ ] |
| Test | 29 — Monitoring | [ ] |
