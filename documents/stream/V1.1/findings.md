# Stream Mimarisi — Bulgular ve Yol Haritası V1.1

**Tarih:** 2026-09-13  
**Kapsam:** LiveKit mevcut durum analizi · Mirror Oda geçiş planı · mediasoup uzun vadeli hedef  
**Topoloji referansı:** `deploy/scale/V1.3/final.md`  
**Nihai hedef:** Her biri 2Gbps/unmetered olan node1-tipi node'lar ekleyerek tüm kapasiteyi tek bir kaynak havuzu olarak kullanan, binlerce eşzamanlı izleyiciyi kaldırabilen streaming altyapısı

---

## 1. Mevcut Topoloji — Stream Açısından

### 1.1 Node Kapasiteleri (Stream İçin)

| Node | Sağlayıcı | Bant Genişliği | LiveKit Durumu | Streaming Rolü |
|------|-----------|---------------|----------------|----------------|
| **node1** | OVHcloud Frankfurt | **2 Gbps / unmetered** | ✅ Production | Ana SFU — tüm prod yayınlar burada |
| gateway | netcup Nürnberg | 1 Gbps / 24h ort. >100 Mbps → throttle | ❌ Yok | Sadece signaling proxy (WebSocket) |
| node2 | VPSHostingService Buffalo | 1 Gbps shared | ❌ Yok | AI Proxy — LiveKit için uygun değil |
| node3 | Zap-Hosting Ashburn | 1 Gbps / **33TB/ay sonrası 10 Mbps throttle** | ⚠️ Sadece staging | Staging SFU — prod mirror için uygunsuz |

**Kritik tespitler:**
- Production streaming'i taşıyan tek node: **node1**
- Gateway medya trafiğini görmez — UDP/RTP doğrudan node1'e gider (`135.125.175.223:50000-60000`)
- node3'ün bant genişliği sınırı (33TB/ay cap) onu production mirror'dan dışarıda bırakır
- node2 shared bant genişliği LiveKit için uygun değil

**Sonuç:** Scaling için eklenecek yeni node'lar **node1 eşdeğeri** olmalı: OVHcloud (veya benzeri), 2Gbps/unmetered.

---

### 1.2 Mevcut LiveKit Trafik Akışı

```
Flutter (sinyal)
    │
    ▼
wss://teqlif.com/rtc
    │
    ▼
Cloudflare → gateway (nginx) → node1:7880   ← WebSocket sinyal
                                    │
Flutter (medya) ──────────────────▶ node1:50000-60000/UDP   ← RTP medya (gateway bypass)
                                    │
                               LiveKit SFU
                               (pure SFU — transcoding yok)
                                    │
                              Tüm viewer'lar
                              (node1'den beslenyor)
```

Sinyal Cloudflare → gateway üzerinden geçiyor ama medya (video paketleri) doğrudan node1'e gidiyor. Bu sayede gateway'in 100 Mbps ortalama limiti streaming'i etkilemiyor.

---

### 1.3 Mevcut LiveKit Konfigürasyonu

**Dosya:** `deploy/scale/V1.3/node1/livekit.yaml`

| Parametre | Değer | Notlar |
|-----------|-------|--------|
| `node_ip` | `135.125.175.223` | node1 public IP — medya paketleri bu IP'den gönderilir |
| `use_external_ip` | `false` | IP sabit tanımlanmış |
| `max_participants` (prod) | **500** | Hard limit — bu değeri geçen odaya katılım reddedilir |
| `max_participants` (staging) | **100** | node3 livekit.yaml |
| Mod | Pure SFU | Transcoding yok — CPU yükü minimal |
| TURN | Etkin | Kısıtlı ağlar için fallback |

**⚠️ Dikkat:** `max_participants: 500` hard limit şu an hem kapasite hem de güvenlik sınırı olarak çalışıyor. Mirror oda olmadan tek odada bu sınırı artırmak node1'i riske atar.

---

### 1.4 Mevcut Kod Haritası

| Konu | Dosya | Satır |
|------|-------|-------|
| Config (tek LIVEKIT_URL) | `app/config.py` | 21–34 |
| Token üretimi | `app/use_cases/streams/stream_utils.py` | 58–83 |
| Oda ismi: `stream_{user_id}_{uuid[:8]}` | `app/use_cases/streams/commands/start_stream.py` | 62 |
| Yayıncı başlatma | `app/routers/streams.py` | 224–238 |
| Viewer join endpoint | `app/routers/streams.py` | 307–313 |
| Viewer join + token üretimi | `app/use_cases/streams/commands/join_stream.py` | 20–53 |
| Co-host izin yükseltme | `app/use_cases/streams/commands/cohost_commands.py` | 43–102 |
| LiveKit webhook handler | `app/routers/webhooks.py` | 26–60 |
| Viewer count WS eventi | `app/routers/webhooks.py` | 211–258 |
| Stream finalizasyonu | `app/use_cases/streams/stream_finalizer.py` | 15–79 |
| Response schema | `app/schemas/stream.py` | 56–72 |
| DB model: LiveStream | `app/models/stream.py` | 10–33 |
| DB model: Auction → Stream FK | `app/models/auction.py` | 13 |

---

### 1.5 Servis Ayrımı — En Büyük Avantaj

```
Video (LiveKit)      ←── RTP/WebRTC medya — node bazlı
Bid (FastAPI WS)     ←── JSON, stream_id bazlı — node'dan bağımsız
Chat (FastAPI WS)    ←── JSON, stream_id bazlı — node'dan bağımsız
Analytics            ←── Redis + PostgreSQL — node'dan bağımsız
```

Flutter'daki "Teklif Ver" butonu ve chat **hangi LiveKit node'una bağlı olunduğundan tamamen bağımsız çalışıyor.** Bu ayrım mirror oda ve mediasoup geçişini doğrudan mümkün kılıyor — Flutter'da hiçbir değişiklik gerekmeden video katmanı yatay ölçeklenebilir.

---

## 2. Kapasite Hesabı

### 2.1 node1 Mevcut Limitler

| Çözünürlük | Viewer başı bant genişliği | 2 Gbps ile maks. viewer | Mevcut hard limit |
|------------|--------------------------|------------------------|-------------------|
| 1080p | ~5 Mbps | ~400 kişi | 500 (livekit.yaml) |
| 720p | ~2.5 Mbps | ~800 kişi | 500 (livekit.yaml) |
| 480p | ~1 Mbps | ~2000 kişi | 500 (livekit.yaml) |

**Not:** CPU şifreleme yükü (SRTP/DTLS) gerçek limiti port dolmadan getirebilir. Her UDP paketi anlık şifrelenir. Pratikte 720p'de ~600–700 viewer CPU darboğazı yaratmaya başlayabilir.

Mevcut `max_participants: 500` limiti zaten bant genişliği tavanının altında — gerçek darboğaz livekit.yaml konfigürasyonu.

### 2.2 node1-Tipi Node Eklenince Toplam Kapasite

Her eklenen node1-eşdeğeri (2Gbps/unmetered):

| Node sayısı | 720p kapasitesi | 480p kapasitesi |
|-------------|-----------------|-----------------|
| 1 (mevcut) | ~700 viewer | ~2000 viewer |
| 2 (node1 + node4) | ~1400 viewer | ~4000 viewer |
| 3 (node1 + node4 + node5) | ~2100 viewer | ~6000 viewer |

---

## 3. Faz 1 — LiveKit Mirror Oda (Şimdi Yapılabilir)

### 3.1 Önkoşul: node4 (node1-Eşdeğeri)

Mirror oda için eklenmesi gereken yeni node özellikleri:

| Parametre | Gereksinim | node1 Referans |
|-----------|-----------|----------------|
| Sağlayıcı | OVHcloud veya eşdeğeri | OVHcloud SAS Frankfurt |
| Bant genişliği | **2 Gbps / unmetered** | 2 Gbps fixed / Unlimited |
| CPU | ≥ 4 çekirdek | Intel Haswell 6 çekirdek |
| RAM | ≥ 8 GB | 11.4 GiB |
| WireGuard IP | `10.10.0.5` (node4) | `10.10.0.1` |

Yeni node deploy edilince:
- `bootstrap_node4.sh` (node1 bootstrap'i temel alarak)
- WireGuard mesh'e eklenir (diğer tüm node'lara peer)
- LiveKit kurulur, konfigüre edilir
- UFW kuralları: UDP 50000-60000, TCP/UDP 7882, TCP 5349, UDP 3478
- `TEQLIF_ENV_FILE` `/etc/environment`'a eklenir

---

### 3.2 Mimari

```
                  ┌──────────────────────────────────────┐
                  │            FastAPI (node1)            │
                  │        MirrorOrchestrator             │
                  │   - viewer sayacı (Redis, per-node)  │
                  │   - threshold tespiti                 │
                  │   - yeni viewer'ı yönlendirme        │
                  └───────────┬──────────────────────────┘
                              │
        ┌─────────────────────┼──────────────────────┐
        ▼                     ▼                      ▼
   LiveKit node1         LiveKit node4          LiveKit node5
   stream_42_a3f9bc01    mirror_42_0001         mirror_42_0002
   [Yayıncı burada]      [Relay bot]            [Relay bot]
   2Gbps / unmetered     2Gbps / unmetered      2Gbps / unmetered
   ~700 viewer           ~700 viewer            ~700 viewer
        │                     │                      │
        └─────────────────────┴──────────────────────┘
                              │
                    FastAPI WebSocket (node1)
                    Bid · Chat · Analytics
                    (stream_id bazlı — tüm viewer'lar aynı kanalda)
```

Yayıncı daima node1'deki ana odaya bağlıdır. FastAPI, arka planda ana odayı diğer node'lara relay eder. Yeni gelen viewer'lar en az dolu node'a yönlendirilir. Bid/chat WebSocket bağlantıları `stream_id` bazlı çalıştığından hangi LiveKit node'unda olunduğu fark etmez.

---

### 3.3 Gerekli Değişiklikler

#### 3.3.1 Config — Çoklu LiveKit Node

`app/config.py`:
```python
# Format: "wss://node1/rtc|apikey1|secret1,wss://node4/rtc|apikey2|secret2"
livekit_nodes: str = ""

@property
def livekit_node_list(self) -> list[dict]:
    if not self.livekit_nodes:
        # Geriye dönük uyumluluk: tek node
        return [{"url": self.livekit_url, "api_key": self.livekit_api_key,
                 "api_secret": self.livekit_api_secret,
                 "api_url": self.livekit_api_base, "node_id": "node1"}]
    nodes = []
    for i, entry in enumerate(self.livekit_nodes.split(",")):
        url, key, secret = entry.strip().split("|")
        nodes.append({"url": url, "api_key": key, "api_secret": secret,
                       "api_url": url.replace("wss://","https://").replace("/rtc",""),
                       "node_id": f"node{i+1}"})
    return nodes
```

`.env.production`'a eklenir (node4 hazır olduğunda):
```
LIVEKIT_NODES=wss://teqlif.com/rtc|key1|secret1,wss://node4-wg/rtc|key2|secret2
```

#### 3.3.2 DB — Mirror Oda Tablosu

```sql
CREATE TABLE stream_mirror_rooms (
    id           SERIAL PRIMARY KEY,
    stream_id    INTEGER      NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    room_name    VARCHAR(120) NOT NULL UNIQUE,
    node_id      VARCHAR(50)  NOT NULL,   -- "node1", "node4", "node5"
    livekit_url  TEXT         NOT NULL,
    is_primary   BOOLEAN      DEFAULT FALSE,
    viewer_count INTEGER      DEFAULT 0,
    relay_egress_id TEXT,                 -- LiveKit Egress ID (relay durdurma için)
    created_at   TIMESTAMPTZ  DEFAULT NOW()
);
CREATE INDEX ix_smr_stream_id ON stream_mirror_rooms(stream_id);
```

Yeni alembic revision gerektirir.

#### 3.3.3 MirrorOrchestrator Servisi

`app/services/mirror_orchestrator.py` — yeni dosya:

```python
MIRROR_THRESHOLD = 500   # Bu viewer sayısını geçince yeni mirror aç
                          # (livekit.yaml max_participants ile uyumlu)
MAX_MIRRORS_PER_STREAM = len(settings.livekit_node_list)

class MirrorOrchestrator:

    async def get_join_node(self, stream_id: int) -> dict:
        """En az dolu LiveKit node'unu döner. Mirror yoksa primary node'u döner."""

    async def maybe_create_mirror(self, stream_id: int) -> None:
        """
        Toplam viewer sayısı MIRROR_THRESHOLD'u geçtiyse ve boş node varsa
        yeni mirror oda açar + relay başlatır. ARQ worker task olarak çağrılır.
        """

    async def get_viewer_counts(self, stream_id: int) -> dict[str, int]:
        """Redis'ten her node'daki viewer sayısını döner."""
        # Redis key pattern: live:viewer_count:{stream_id}:{node_id}
```

#### 3.3.4 Relay Bot

Mirror oda açılınca yayın primary node'dan mirror node'a iletilir. İki seçenek:

**Seçenek A — LiveKit Egress API (tercih edilen):**
```python
async def start_relay(primary_room: str, mirror_room: str,
                      from_node: dict, to_node: dict) -> str:
    # LiveKit Egress: primary odayı RTMP/WebRTC olarak mirror node'a ilet
    # egress_id döner — stream sonunda durdurmak için saklanır
```

**Seçenek B — FFmpeg bot (Egress lisansı olmadan):**
```bash
# Primary node'dan RTMP çek, mirror node'a bas
ffmpeg -i rtmp://10.10.0.1/live/{room_name} \
       -c copy -f rtmp \
       rtmp://10.10.0.5/live/{mirror_room_name}
```

#### 3.3.5 JoinStreamCommand Değişikliği

`app/use_cases/streams/commands/join_stream.py`:

```python
# Mevcut
livekit_url = settings.livekit_url
room_name   = stream.room_name

# Yeni
node      = await mirror_orchestrator.get_join_node(stream.id)
livekit_url = node["url"]
room_name   = node["room_name"]  # primary veya mirror oda adı
```

`JoinTokenOut` response yapısı değişmez — Flutter aynı JSON'u alır. Sadece `livekit_url` ve `room_name` farklı bir node'a işaret edebilir.

#### 3.3.6 Webhook Handler Değişikliği

`app/routers/webhooks.py` — per-node viewer sayacı:

```
# Mevcut
live:viewer_count:{stream_id}  →  N

# Yeni (ek Redis key'ler)
live:viewer_count:{stream_id}:node1  →  N
live:viewer_count:{stream_id}:node4  →  M
live:viewer_count:{stream_id}        →  N + M  (toplam — mevcut davranış korunur)
```

Flutter'a giden `viewer_count` WS eventi toplam sayıyı gösterir. Mirror varlığı Flutter'a transparan kalır.

#### 3.3.7 livekit.yaml — max_participants Artırımı

Mirror oda devreye girince her node'un `max_participants` limiti yeniden anlamlı hale gelir.

Node1 için `deploy/scale/V1.3/node1/livekit.yaml`:
```yaml
room:
  max_participants: 700   # 500'den artır — node başı 700 viewer
```

Her yeni node için aynı değer.

---

### 3.4 Flutter Tarafında Değişiklik Yok

Flutter şunları alıyor: `{ room_name, livekit_url, token, host_livekit_identity }`

Relay bot, host track'ini mirror odaya iletirken yayıncının user ID'sini (`host_livekit_identity`) korur. Flutter mirror odaya girdiğinde host track'ini bulmak için aynı kodu çalıştırır. Bid/chat WebSocket'leri `stream_id` bazlı çalışıyor, room_name'e bağlı değil.

---

### 3.5 WireGuard — Yeni Node Entegrasyonu

Her yeni node (node4, node5…) mevcut WireGuard mesh'e eklenir:

```
node1   10.10.0.1  ←──── tam peer
gateway 10.10.0.2  ←──── tam peer
node2   10.10.0.3  ←──── tam peer
node3   10.10.0.4  ←──── tam peer
node4   10.10.0.5  ←──── yeni (LiveKit mirror)
node5   10.10.0.6  ←──── yeni (LiveKit mirror)
```

node4 için wg0.conf şablonu: `deploy/scale/resources/node4/` altında oluşturulacak.

Relay bot WireGuard IP'ler üzerinden haberleşir — public IP yerine mesh IP:
```
node1 LiveKit → 10.10.0.5:7880 (node4 WireGuard IP)
```

---

### 3.6 Prometheus — Yeni Node Scrape

`deploy/scale/V1.3/node3/prometheus.yml`'e eklenir (her yeni node için):
```yaml
- job_name: 'livekit-node4'
  static_configs:
    - targets: ['10.10.0.5:7881']  # LiveKit metrics
- job_name: 'node-node4'
  static_configs:
    - targets: ['10.10.0.5:9100']  # node_exporter
```

---

### 3.7 Implementasyon Sırası

1. `stream_mirror_rooms` tablosu + alembic migration
2. `app/config.py` multi-node config (`LIVEKIT_NODES`)
3. `MirrorOrchestrator` — node seçimi + Redis per-node tracking
4. `JoinStreamCommand` — orchestrator entegrasyonu
5. Webhook handler — per-node viewer count
6. Relay bot (Egress veya FFmpeg)
7. ARQ worker task — `maybe_create_mirror` threshold trigger
8. `livekit.yaml` max_participants güncelleme
9. node4 fiziksel kurulum + bootstrap + WireGuard mesh
10. `.env.production` — `LIVEKIT_NODES` değerleri
11. Prometheus scrape ekleme
12. Staging'de 2 node mirror testi

**Tahmini süre:** 4–6 gün (kod) + node4 kurulum süresi

---

## 4. Faz 2 — mediasoup Geçişi (Uzun Vadeli Hedef)

### 4.1 Neden mediasoup?

| | LiveKit OSS + Mirror | mediasoup + PipeTransport |
|--|---------------------|--------------------------|
| Lisans | Apache 2.0 | ISC (tam ticari özgür) |
| Dağıtık oda (tek oda → çok node) | ❌ Mirror: relay kopyası | ✅ Gerçek cascading |
| Relay overhead | Video 2x encode + iletim | ❌ Yok — RTP doğrudan tünellenir |
| Flutter SDK | ✅ Hazır | ❌ flutter_webrtc ile kendin yaz |
| Oda yönetimi | ✅ Dahili | ❌ Sen yazarsın |
| Recording/Egress | ✅ Dahili | ❌ Sen yazarsın |
| CPU verimliliği | İyi | Çok iyi (C++ çekirdeği) |
| Özelleştirme | Kısıtlı | Tam kontrol |

LiveKit Mirror'ın zayıf noktası: video relay ile iletilir — her mirror node yayını bir kez daha alıp dağıtır, bu CPU ve bant genişliği overhead'i demek. mediasoup PipeTransport'ta ise RTP paketleri doğrudan bir node'dan diğerine tünellenir; orijinal encode sadece bir kez yapılır.

### 4.2 PipeTransport — Gerçek Cascading

```
Yayıncı → Worker1 (node1)
                │
         PipeTransport (WireGuard mesh üzerinden RTP tüneli)
                │
         Worker2 (node4) → 700 viewer
                │
         PipeTransport
                │
         Worker3 (node5) → 700 viewer

Toplam: 3 node × ~700 = ~2100 viewer @ 720p
Video encode: sadece 1 kez (yayıncı → node1)
```

### 4.3 Mimari Tasarım

```
                    ┌─────────────────────────────────┐
                    │   Signaling Server (Node.js)    │
                    │   Her node1-tipi node'da çalışır│
                    │   - Oda yönetimi                │
                    │   - JWT auth (FastAPI ile shared)│
                    │   - PipeTransport koordinasyonu │
                    └──────────────┬──────────────────┘
                                   │ REST
                    ┌──────────────▼──────────────────┐
                    │         FastAPI (node1)          │
                    │   (Bid · Chat · Analytics)       │
                    └──────────────────────────────────┘
                                   │
         ┌─────────────────────────┼──────────────────────┐
         ▼                         ▼                      ▼
  mediasoup node1           mediasoup node4        mediasoup node5
  (Node.js process)         (PipeTransport)        (PipeTransport)
  Yayıncı + 700 viewer      700 viewer             700 viewer
  WireGuard: 10.10.0.1      10.10.0.5              10.10.0.6
```

### 4.4 Gerekli Geliştirmeler

#### Signaling Server (Node.js — yeni servis, her node'da)

```
deploy/scale/V2.0/
└── signaling/
    ├── server.js          ← Express + ws
    ├── room_manager.js    ← Oda oluşturma, PipeTransport yönetimi
    ├── worker_pool.js     ← CPU core başı 1 mediasoup worker
    └── package.json
```

Systemd servisi: `teqlif-signaling.service` — her node1-tipi node'da.

#### Flutter Tarafı — flutter_webrtc

LiveKit Flutter SDK çıkar, `flutter_webrtc` paketi girer:

```dart
// Mevcut LiveKit SDK:
await room.connect(livekitUrl, token);

// Yeni mediasoup signaling:
final ws = WebSocketChannel.connect(signalingUrl);
await _createRecvTransport(ws);
await _consumeTrack(ws, producerId: hostProducerId);
```

Bu kısım en büyük Flutter değişikliği — tahminen 1–2 hafta.

#### FastAPI Değişiklikleri

- `make_livekit_token()` → `make_signaling_token()` (aynı JWT yapısı, farklı claim'ler)
- `JoinTokenOut.livekit_url` → `signaling_url`
- Webhook handler → mediasoup event formatına uyarlanır
- Co-host logic → mediasoup `updateProducerPermissions`

#### Feature Flag ile Sıfır Kesintili Geçiş

```python
# config.py
sfu_backend: str = "livekit"  # "livekit" veya "mediasoup"
```

```python
# join_stream.py
if settings.sfu_backend == "mediasoup":
    return await MediasoupJoinCommand(uow).execute(...)
else:
    return await LivekitJoinCommand(uow).execute(...)
```

Staging'de mediasoup aktif, production'da LiveKit — yeterince test edildikten sonra tek satır değişiklikle production geçişi. Geri dönüş yine tek satır.

### 4.5 Geçiş Tetikleyici

mediasoup geçişi için gerçekçi eşik: **tek bir müzayede odasında sürekli 1500+ eşzamanlı viewer** görülmesi ve relay overhead'inin (mirror oda yaklaşımı) ölçülebilir gecikme veya senkronizasyon sorununa yol açması.

Bu eşiğe ulaşılmadan mediasoup geçişi erken optimizasyon olur.

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
Şimdi (V1.3)        node4 hazır       node4 aktif        Gerekirse
      │                  │                 │                   │
      ▼                  ▼                 ▼                   ▼
node1 tek node      node4 sipariş    Faz 1 tamamlandı    Faz 2 başlar
500 max viewer      node1-eşdeğeri   Mirror Oda aktif    mediasoup
(livekit.yaml)      OVHcloud 2Gbps   ~1400 viewer        PipeTransport
                    WireGuard mesh'e  (node1+node4)       gerçek cascading
                    eklenir           Flutter değişmez    ~N×700 viewer
```

---

### Kilometre Taşları

**KT-0 (node4 hazır — önkoşul):**
- [ ] node4 sipariş edildi (OVHcloud, 2Gbps/unmetered)
- [ ] `bootstrap_node4.sh` oluşturuldu (node1 bootstrap temel alınarak)
- [ ] WireGuard mesh'e eklendi (10.10.0.5)
- [ ] LiveKit kuruldu ve konfigüre edildi
- [ ] Prometheus scrape eklendi

**KT-1 (Faz 1 tamamlandı):**
- [ ] `stream_mirror_rooms` tablosu aktif
- [ ] `MirrorOrchestrator` çalışıyor
- [ ] `livekit.yaml` max_participants 700'e yükseltildi (node1 + node4)
- [ ] Relay bot aktif (Egress veya FFmpeg)
- [ ] Staging'de 2 node mirror testi geçti
- [ ] Viewer count toplamı doğru gösteriliyor
- [ ] Flutter'da hiçbir değişiklik yapılmadı

**KT-2 (Faz 2 staging):**
- [ ] mediasoup signaling server node3 staging'de çalışıyor
- [ ] Flutter flutter_webrtc ile staging'e bağlanabiliyor
- [ ] Bid/chat aynı şekilde çalışıyor
- [ ] PipeTransport ile 2 node cascading test edildi

**KT-3 (Faz 2 production):**
- [ ] `sfu_backend=mediasoup` production'da aktif
- [ ] N node PipeTransport cascading stabil
- [ ] LiveKit servisleri opsiyonel olarak devre dışı bırakılabilir
- [ ] Kapasite testi: hedef viewer sayısı simüle edildi

---

## 6. Kararlar ve Gerekçeler

| Karar | Gerekçe |
|-------|---------|
| node3'ü production mirror olarak kullanmamak | 33TB/ay bant genişliği cap → throttle riski; staging LiveKit olarak kalır |
| node2'yi LiveKit için kullanmamak | 1Gbps shared — video trafiği için yetersiz ve unreliable |
| node4 için OVHcloud/2Gbps zorunluluğu | node1 ile aynı unmetered profil — tahmin edilebilir kapasite |
| Faz 1'de LiveKit'i korumak | Flutter SDK hazır; mediasoup geçişi için henüz erken |
| Feature flag ile geçiş | Production'da sıfır kesinti; geri dönüş tek satır |
| Relay için Egress (tercih) / FFmpeg (fallback) | PipeTransport Faz 2'ye saklandı; Faz 1 daha basit tutuldu |
| Flutter'da değişiklik yok (Faz 1) | Bid/chat zaten ayrık — risk sıfır |
| mediasoup ISC lisansı | Ticari kullanım için tam özgür; LiveKit'in enterprise kısıtı yok |
| Pion/Janus yerine mediasoup | En aktif topluluk; PipeTransport en iyi cascading desteği |
| mediasoup geçişini ertelemek | 1500+ viewer eşiğine gelene kadar erken optimizasyon olur |
