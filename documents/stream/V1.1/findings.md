# Stream Mimarisi — Bulgular ve Yol Haritası V1.1

**Tarih:** 2026-09-13  
**Kapsam:** LiveKit mevcut durum analizi · Mirror Oda geçiş planı · mediasoup uzun vadeli hedef  
**Nihai hedef:** Tüm VPS kapasitesini (toplamda 6 Gbps+) tek bir kaynak havuzu olarak kullanabilen, binlerce eşzamanlı izleyiciyi kaldırabilen, kendi kontrolümüzdeki SFU mimarisi

---

## 1. Mevcut Durum — LiveKit Entegrasyonu

### 1.1 Mimari Özet

```
Flutter ──── wss://teqlif.com/rtc ──── LiveKit (node1)
                                            │
FastAPI ─── livekit_api_url ───────── LiveKit Admin API
                                            │
              WebSocket/Redis ────── Bid · Chat · Analytics
```

**Servis ayrımı (büyük avantaj):**
- **Video:** LiveKit ← sadece RTP/WebRTC medya trafiği
- **Bid:** FastAPI WebSocket ← JSON, node'dan bağımsız
- **Chat:** FastAPI WebSocket ← JSON, node'dan bağımsız
- **Analytics:** Redis + PostgreSQL ← node'dan bağımsız

Bu ayrım mirror oda ve mediasoup geçişini doğrudan mümkün kılıyor. Flutter'daki "Teklif Ver" butonu ve chat, hangi LiveKit node'una bağlı olunduğundan tamamen bağımsız çalışıyor.

---

### 1.2 Mevcut Kod Haritası

| Konu | Dosya | Satır |
|------|-------|-------|
| Config (tek LIVEKIT_URL) | `app/config.py` | 21–34 |
| Token üretimi | `app/use_cases/streams/stream_utils.py` | 58–83 |
| Oda ismi oluşturma | `app/use_cases/streams/commands/start_stream.py` | 62 |
| Yayıncı başlatma endpoint | `app/routers/streams.py` | 224–238 |
| Viewer join endpoint | `app/routers/streams.py` | 307–313 |
| Viewer join logic + token | `app/use_cases/streams/commands/join_stream.py` | 20–53 |
| Co-host izin yükseltme | `app/use_cases/streams/commands/cohost_commands.py` | 43–102 |
| LiveKit webhook handler | `app/routers/webhooks.py` | 26–60 |
| Viewer count WS eventi | `app/routers/webhooks.py` | 211–258 |
| Stream finalizasyonu | `app/use_cases/streams/stream_finalizer.py` | 15–79 |
| Response schema | `app/schemas/stream.py` | 56–72 |
| DB model: LiveStream | `app/models/stream.py` | 10–33 |
| DB model: Auction (FK) | `app/models/auction.py` | 13 |

---

### 1.3 Join Akışı (Mevcut)

```
Flutter → POST /api/streams/{id}/join
              ↓
         JoinStreamCommand
              ↓
         make_livekit_token(room_name, user, can_publish=False)
              ↓
         Response: { room_name, livekit_url, token, host_livekit_identity }
              ↓
Flutter → LiveKit SDK.connect(livekit_url, token)
```

**`JoinTokenOut` şeması:**
```json
{
  "stream_id": 42,
  "room_name": "stream_7_a3f9bc01",
  "livekit_url": "wss://teqlif.com/rtc",
  "token": "<JWT>",
  "host_livekit_identity": "7"
}
```

`host_livekit_identity` = `str(host.id)` — Flutter bu kimlikle host'un video track'ini buluyor.

---

### 1.4 Oda İsimlendirme

```python
room_name = f"stream_{user_id}_{uuid4().hex[:8]}"
# Örnek: stream_42_a3f9bc01
```

Redis'te ters-lookup için:
```
live:room_to_stream:{room_name} → "{stream_id}:{host_id}"
```

---

### 1.5 Kritik Limit: Tek LIVEKIT_URL

Şu an sistemde multi-node seçim mantığı **yok.** Tüm odalar tek bir LiveKit sunucusuna gidiyor. Mirror oda için bu değişmeli.

---

## 2. Kapasite Hesabı

### 2.1 Tek Node Limitleri (node1 — 2 Gbps unmetered)

| Çözünürlük | Viewer başı bant genişliği | Maks. eşzamanlı viewer |
|------------|--------------------------|----------------------|
| 1080p | ~5 Mbps | ~400 kişi |
| 720p | ~2.5 Mbps | ~800 kişi |
| 480p | ~1 Mbps | ~2000 kişi |

**Not:** CPU şifreleme yükü (SRTP/DTLS) gerçek limiti port dolmadan getirebilir. Her UDP paketi anlık şifrelenir. Pratikte 720p'de ~600–700 viewer CPU darboğazı yaratmaya başlayabilir (VPS CPU'ya bağlı).

### 2.2 Mirror Oda ile Toplam Kapasite (3 node)

| Çözünürlük | Tek node | 3 node mirror | Notlar |
|------------|----------|---------------|--------|
| 720p | ~700 | ~2100 | Önerilen başlangıç |
| 480p | ~2000 | ~6000 | Yüksek izleyici senaryosu |
| 1080p | ~400 | ~1200 | Premium yayın |

---

## 3. Faz 1 — LiveKit Mirror Oda (Şimdi Yapılabilir)

### 3.1 Konsept

Bid ve chat FastAPI'de kaldığı için video katmanı yatay ölçeklenebilir. Yayıncı tek bir node'a yayın yapar; FastAPI arka planda bu yayını diğer node'lara relay eder. Yeni gelen viewer'lar otomatik olarak en az dolu node'a yönlendirilir.

```
                  ┌─────────────────────────────────┐
                  │           FastAPI                │
                  │   MirrorOrchestrator             │
                  │   - viewer count tracking        │
                  │   - node load balancing          │
                  └──────────┬──────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   LiveKit node1        LiveKit node2        LiveKit node3
   stream_42_a3f9bc01   mirror_42_0001       mirror_42_0002
   [Yayıncı burada]     [Relay bot]          [Relay bot]
        │                    │                    │
   200 viewer           200 viewer           200 viewer
        │                    │                    │
        └────────────────────┴────────────────────┘
                             │
                    FastAPI WebSocket
                    (Bid · Chat — hepsi burada)
```

### 3.2 Gerekli Değişiklikler

#### 3.2.1 Config — Çoklu LiveKit Node Desteği

`app/config.py`'e eklenecek:

```python
# Birden fazla LiveKit node tanımı
# Format: "wss://node1/rtc|apikey1|apisecret1,wss://node2/rtc|apikey2|apisecret2"
livekit_nodes: str = ""

@property
def livekit_node_list(self) -> list[dict]:
    """LIVEKIT_NODES env var'ından node listesi parse et."""
    if not self.livekit_nodes:
        # Geriye dönük uyumluluk: tek node
        return [{
            "url": self.livekit_url,
            "api_key": self.livekit_api_key,
            "api_secret": self.livekit_api_secret,
            "api_url": self.livekit_api_base,
            "node_id": "node1",
        }]
    nodes = []
    for i, entry in enumerate(self.livekit_nodes.split(",")):
        url, key, secret = entry.strip().split("|")
        nodes.append({
            "url": url, "api_key": key, "api_secret": secret,
            "api_url": url.replace("wss://", "https://").replace("/rtc", ""),
            "node_id": f"node{i+1}",
        })
    return nodes
```

`.env.production` ve `.env.staging`'e eklenecek:
```
LIVEKIT_NODES=wss://teqlif.com/rtc|key1|secret1,wss://node2-internal/rtc|key2|secret2
```

#### 3.2.2 DB — Mirror Oda Tablosu

```sql
CREATE TABLE stream_mirror_rooms (
    id          SERIAL PRIMARY KEY,
    stream_id   INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    room_name   VARCHAR(120) NOT NULL UNIQUE,
    node_id     VARCHAR(50)  NOT NULL,  -- "node1", "node2", "node3"
    livekit_url TEXT         NOT NULL,
    is_primary  BOOLEAN      DEFAULT FALSE,
    viewer_count INTEGER     DEFAULT 0,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
);
CREATE INDEX ix_smr_stream_id ON stream_mirror_rooms(stream_id);
```

**Alembic migration:** Yeni revision oluşturulacak.

#### 3.2.3 Mirror Orchestrator Servisi

`app/services/mirror_orchestrator.py` — yeni dosya:

```python
MIRROR_THRESHOLD = 600   # Bu sayıyı geçince yeni mirror aç
MAX_MIRRORS     = 3      # Toplam node sayısı kadar

class MirrorOrchestrator:
    async def get_join_node(self, stream_id: int) -> dict:
        """
        Viewer join isteğinde en az dolu node'u döner.
        Mirror yoksa primary node'u döner.
        """

    async def maybe_create_mirror(self, stream_id: int) -> None:
        """
        Toplam viewer sayısı MIRROR_THRESHOLD'u geçtiyse
        ve boş node varsa yeni mirror oda açar + relay bot başlatır.
        Worker task olarak çalışır.
        """

    async def get_node_viewer_counts(self, stream_id: int) -> dict[str, int]:
        """Redis'ten her node'daki viewer sayısını getirir."""
```

#### 3.2.4 Relay Bot

`app/services/relay_bot.py` — yeni dosya:

Mirror oda açıldığında LiveKit'in **Egress API** kullanılarak yayın primary node'dan mirror node'a iletilir:

```python
async def start_relay(primary_room: str, mirror_room: str,
                      from_node: dict, to_node: dict) -> str:
    """
    LiveKit Egress ile primary odadaki yayını
    mirror node'daki odaya RTMP/WebRTC olarak ilet.
    egress_id döner — sonradan durdurmak için saklanır.
    """
    egress_client = EgressServiceClient(from_node["api_url"],
                                         from_node["api_key"],
                                         from_node["api_secret"])
    # RoomCompositeEgressRequest ile mirror node'a stream
    ...
```

**Alternatif (Egress lisansı olmadan):** FFmpeg bot — primary node'dan RTMP çekip mirror node'a RTMP atar. Daha az elegant ama tamamen ücretsiz:

```bash
ffmpeg -i rtmp://node1-internal/live/{room} \
       -c copy \
       -f rtmp rtmp://node2-internal/live/{mirror_room}
```

#### 3.2.5 JoinStreamCommand Değişikliği

`app/use_cases/streams/commands/join_stream.py` — mevcut join logic'e node seçimi eklenir:

```python
# Mevcut: tek sabit livekit_url
livekit_url = settings.livekit_url

# Yeni: MirrorOrchestrator'dan en az dolu node
node = await mirror_orchestrator.get_join_node(stream_id)
livekit_url = node["url"]
room_name   = node["room_name"]   # primary veya mirror oda
```

`JoinTokenOut` response'u değişmez — Flutter aynı yapıyı alır, sadece `livekit_url` ve `room_name` farklı node'a işaret edebilir.

#### 3.2.6 Webhook Handler Değişikliği

`app/routers/webhooks.py` — viewer count event'leri hangi node'dan geldiğine göre Redis key'i günceller:

```
live:viewer_count:{stream_id}:node1  →  N
live:viewer_count:{stream_id}:node2  →  M
live:viewer_count:{stream_id}       →  N + M  (toplam — mevcut davranış korunur)
```

Böylece Flutter'a giden `viewer_count` WS eventi toplam sayıyı gösterir, mirror varlığı Flutter'a transparan kalır.

---

### 3.3 Flutter Tarafında Değişiklik Yok

Flutter şunları alıyor: `{ room_name, livekit_url, token, host_livekit_identity }`

Mirror odada `host_livekit_identity` aynı kalır (host'un user ID'si). Relay bot, host track'ini mirror odaya iletirken aynı identity string'ini kullanır. Flutter mirror odaya girdiğinde host track'ini bulmak için aynı kodu çalıştırır.

Bid/chat WebSocket'leri `stream_id` bazında çalışıyor, room_name'e bağlı değil. Hiçbir Flutter değişikliği gerekmez.

---

### 3.4 Implementasyon Sırası

1. `stream_mirror_rooms` tablosu + alembic migration
2. `app/config.py` multi-node config
3. `MirrorOrchestrator` — node seçimi + Redis tracking
4. `JoinStreamCommand` — orchestrator entegrasyonu
5. Webhook handler — per-node viewer count
6. Relay bot (Egress veya FFmpeg)
7. Worker task — `maybe_create_mirror` threshold trigger
8. `.env.production` / `.env.staging` — `LIVEKIT_NODES` değerleri
9. Test: staging'de 2 node ile mirror senaryosu

**Tahmini süre:** 4–6 gün

---

## 4. Faz 2 — mediasoup Geçişi (Uzun Vadeli Hedef)

### 4.1 Neden mediasoup?

| | LiveKit OSS | mediasoup |
|--|-------------|-----------|
| Lisans | Apache 2.0 | ISC (tam ticari özgür) |
| Cascading (dağıtık oda) | ❌ Enterprise özelliği | ✅ PipeTransport |
| Flutter SDK | ✅ Hazır | ❌ flutter_webrtc ile kendin yaz |
| Oda yönetimi | ✅ Dahili | ❌ Sen yazarsın |
| Recording/Egress | ✅ Dahili | ❌ Sen yazarsın |
| CPU verimliliği | İyi | Çok iyi (C++ çekirdeği) |
| Özelleştirme | Kısıtlı | Tam kontrol |

### 4.2 PipeTransport — Asıl Güç

mediasoup'un diğer SFU'lardan farkı: iki mediasoup sunucusu arasında doğrudan RTP tüneli açılabiliyor.

```
Yayıncı → Worker1 (node1)
                │
         PipeTransport
                │
          Worker2 (node2) → 600 viewer
                │
         PipeTransport
                │
          Worker3 (node3) → 600 viewer
```

Bu yapıda:
- Yayıncı sadece node1'e bağlanır
- node1 → node2 ve node1 → node3 arasında sunucu-sunucu RTP tüneli açılır
- Her node kendi 600 viewer'ını besler
- Toplam kapasite: 1800 viewer @ 720p (3 × 2 Gbps = 6 Gbps)
- LiveKit'teki relay bot hilesine gerek kalmaz, medya tek kez encode edilip dağıtılır

### 4.3 Mimari Tasarım

```
                    ┌──────────────────────────────┐
                    │   Signaling Server (Node.js)  │
                    │   - Oda yönetimi              │
                    │   - Token auth (JWT)          │
                    │   - PipeTransport yönetimi    │
                    └──────────────┬───────────────┘
                                   │ (REST/gRPC)
                    ┌──────────────▼───────────────┐
                    │         FastAPI               │
                    │   (Bid · Chat · Analytics)   │
                    └──────────────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
       mediasoup node1      mediasoup node2      mediasoup node3
       (Node.js process)    (Node.js process)    (Node.js process)
       Yayıncı burada       PipeTransport        PipeTransport
       600 viewer           600 viewer           600 viewer
```

### 4.4 Gerekli Geliştirmeler

#### 4.4.1 Signaling Server (Node.js — yeni servis)

```
deploy/scale/V2.0/
└── signaling/
    ├── server.js         ← Express + ws
    ├── room_manager.js   ← Oda oluşturma, pipe yönetimi
    ├── worker_pool.js    ← mediasoup worker havuzu (CPU core başı 1 worker)
    └── package.json
```

Signaling server şunları sağlar:
- WebSocket üzerinden `createTransport`, `produce`, `consume` mesajları
- JWT doğrulaması (FastAPI ile shared secret)
- PipeTransport kurulumu (threshold aşılınca otomatik)
- Oda kapandığında temizlik

#### 4.4.2 Flutter Tarafı — flutter_webrtc

LiveKit Flutter SDK çıkar, `flutter_webrtc` paketi girer. Signaling WebSocket'i doğrudan Flutter'dan açılır.

```dart
// Mevcut LiveKit SDK çağrısı:
await room.connect(livekitUrl, token);

// Yeni mediasoup signaling:
final ws = WebSocketChannel.connect(signalingUrl);
await _createRecvTransport(ws);
await _consumeTrack(ws, producerId: hostProducerId);
```

Bu kısım en büyük Flutter değişikliği — tahminen 1–2 hafta.

#### 4.4.3 FastAPI Değişiklikleri

- `make_livekit_token()` → `make_signaling_token()` (aynı JWT, farklı claim)
- `JoinTokenOut.livekit_url` → `signaling_url`
- Webhook handler → mediasoup event'leri (farklı format)
- Cohost logic → mediasoup `updateProducerPermissions`

#### 4.4.4 Systemd Servisleri

Her node'da yeni servis:
```ini
[Unit]
Description=teqlif mediasoup signaling
After=network.target

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/signaling
ExecStart=/usr/bin/node server.js
EnvironmentFile=/var/www/teqlif.com/deploy/scale/resources/node1/.env.production
Restart=always
```

### 4.5 Geçiş Stratejisi — Sıfır Kesinti

LiveKit → mediasoup geçişi feature flag ile yapılır:

```python
# config.py
sfu_backend: str = "livekit"  # "livekit" veya "mediasoup"
```

`JoinStreamCommand`:
```python
if settings.sfu_backend == "mediasoup":
    return await MediasoupJoinCommand(uow).execute(...)
else:
    return await LivekitJoinCommand(uow).execute(...)
```

Staging'de mediasoup aktif, production'da LiveKit — yeterince test edildikten sonra production'da flag değiştirilir. Geri dönüş tek satır.

### 4.6 Tahmini Süre

| Görev | Süre |
|-------|------|
| mediasoup signaling server (Node.js) | 5–7 gün |
| Flutter flutter_webrtc entegrasyonu | 7–10 gün |
| FastAPI adaptör katmanı | 2–3 gün |
| PipeTransport cascading logic | 3–4 gün |
| Staging test + stabilizasyon | 5–7 gün |
| Production geçiş + izleme | 2–3 gün |
| **Toplam** | **~4–5 hafta** |

---

## 5. Yol Haritası

```
Şimdi              1 hafta            1 ay              3+ ay
  │                   │                 │                  │
  ▼                   ▼                 ▼                  ▼
Mevcut           Faz 1 tamamlandı   Faz 2 başlar     Faz 2 tamamlandı
LiveKit          Mirror Oda         mediasoup         mediasoup
tek node         (LiveKit üstünde)  signaling server  PipeTransport
                 ~2000 viewer       geliştirme        ~6000+ viewer
                 staging test       staging aktif     production geçiş
```

### Kilometre Taşları

**KT-1 (Faz 1 tamamlandı):**
- [ ] `stream_mirror_rooms` tablosu aktif
- [ ] `MirrorOrchestrator` çalışıyor
- [ ] Staging'de 2 node mirror testi geçti
- [ ] Viewer count toplamı doğru gösteriliyor
- [ ] Flutter'da hiçbir değişiklik olmadı

**KT-2 (Faz 2 staging):**
- [ ] mediasoup signaling server node3'te çalışıyor
- [ ] Flutter flutter_webrtc ile staging'e bağlanabiliyor
- [ ] Bid/chat aynı şekilde çalışıyor
- [ ] PipeTransport ile 2 node cascading test edildi

**KT-3 (Faz 2 production):**
- [ ] `sfu_backend=mediasoup` production'da aktif
- [ ] 3 node PipeTransport cascading stabil
- [ ] LiveKit servisleri devre dışı (node1'de hâlâ port var, ileride kaldırılır)
- [ ] Kapasite testi: 1500+ eşzamanlı viewer simüle edildi

---

## 6. Kararlar ve Gerekçeler

| Karar | Gerekçe |
|-------|---------|
| Faz 1'de LiveKit'i korumak | mediasoup geçişi için henüz erken; mirror oda ile mevcut kapasite 3x artıyor |
| Feature flag ile geçiş | Production'da sıfır kesinti; geri dönüş tek satır |
| Relay için Egress/FFmpeg | PipeTransport Faz 2'ye saklandı; Faz 1 daha basit tutuldu |
| Flutter'da değişiklik yok (Faz 1) | Risk sıfır; bid/chat zaten ayrık |
| mediasoup ISC lisansı | Ticari kullanım için tam özgür, enterprise kısıtı yok |
| Pion/Janus yerine mediasoup | Aktif topluluk, en iyi cascading desteği (PipeTransport), iyi dökümantasyon |
