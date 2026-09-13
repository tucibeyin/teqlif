# Stream Mimarisi — Bulgular ve Yol Haritası V1.1

**Tarih:** 2026-09-13  
**Topoloji referansı:** `deploy/scale/V1.3/final.md`

---

## Hedef

Mevcut altyapının streaming kapasitesini **yazılım değişiklikleriyle** maksimuma taşımak, ardından yeni node eklendiğinde bunun otomatik olarak kapasiteye katkı sağladığı bir mimari kurmak.

**Sıra önemli:**
1. Önce mevcut altyapıdaki yazılımsal dar boğazları çöz → LiveKit mirroring
2. Ardından SFU'yu mediasoup'a geçir → PipeTransport ile gerçek cascading
3. Sonra yeni node ekle → mimari buna hazır, her node tam verimle çalışır

Yeni node satın almadan önce bu sırayı takip etmek kritik. Yeni node'u LiveKit mirror üstüne eklemek, relay overhead'i yaratır (video iki kez işlenir). Aynı node'u mediasoup PipeTransport üstüne eklemek, RTP doğrudan tünellenir — sıfır overhead.

---

## Mevcut Durum Analizi

### Altyapı (Stream Gözüyle)

| Node | Bant Genişliği | LiveKit | Streaming Rolü |
|------|---------------|---------|----------------|
| **node1** | **2 Gbps / unmetered** | ✅ Production | Tüm prod yayınlar burada |
| node3 | 1 Gbps / 33TB cap → 10Mbps throttle | ⚠️ Staging | Prod için uygunsuz — bandwidth cap |
| node2 | 1 Gbps shared | ❌ Yok | AI proxy — video için uygunsuz |
| gateway | 1 Gbps / 100Mbps ort. cap | ❌ Yok | Sadece sinyal proxy |

Medya (UDP/RTP) doğrudan node1'e gidiyor (`135.125.175.223:50000-60000`). Gateway medya trafiğini görmüyor.

### Mevcut Yazılımsal Dar Boğazlar

**1. Tek LIVEKIT_URL — multi-node routing kodu yok**

`app/config.py:72`:
```python
livekit_url: str = "wss://teqlif.com/rtc"  # tek sabit URL
```

`app/use_cases/streams/commands/join_stream.py:47`:
```python
livekit_url = settings.livekit_url  # her viewer aynı node'a gönderilir
```

Yeni bir LiveKit node kurulsa bile bu kodu değiştirmedikçe hiçbir viewer oraya yönlendirilmez.

**2. livekit.yaml hard limit: `max_participants: 500`**

`deploy/scale/V1.3/node1/livekit.yaml`:
```yaml
room:
  max_participants: 500
```

node1 2 Gbps / unmetered bant genişliğiyle 720p'de ~700-800 viewer kaldırabilir. Ama kod bu limiti 500'de tutuyor — donanım kapasitesinin ~%70'i kullanılıyor.

**3. Viewer join'de node seçim mantığı yok**

Tüm viewer'lar tek odaya giriyor. Yük dengeleme, threshold tespiti, otomatik mirror oda açma mekanizması yok.

### Mevcut Kapasite (Yazılımsal Limitlerle)

| Durum | Maks. Viewer | Darboğaz |
|-------|-------------|----------|
| Şu an (livekit.yaml hard limit) | **500** | `max_participants: 500` config |
| Donanım kapasitesi (node1, 720p) | ~700-800 | 2Gbps port + CPU şifreleme |
| Donanım kapasitesi (node1, 480p) | ~2000 | 2Gbps port |

---

## Faz 1 — Mevcut Altyapıda Yazılımsal İyileştirme

**Donanım değişikliği yok. Mevcut node'larla çalışır.**

### 1.1 Ne Yapılacak

- `max_participants` limitini node1'in gerçek kapasitesine yükselt
- Multi-node routing altyapısını yaz — şimdilik tek node, yeni node eklenince otomatik devreye girer
- `JoinStreamCommand`'a node seçim mantığı ekle
- Viewer count'u per-node Redis'te izle

### 1.2 max_participants Artırımı

`deploy/scale/V1.3/node1/livekit.yaml`:
```yaml
room:
  max_participants: 750  # 500'den artır — node1 donanım kapasitesine yakın
```

Bu tek değişiklik, hiçbir kod yazmadan mevcut kapasiteyi **%50 artırır**.

Staging'de (node3 livekit.yaml): 100'de bırakılır.

### 1.3 Multi-Node Routing Altyapısı

#### Config — Çoklu LiveKit Node Desteği

`app/config.py`:
```python
# Format: "wss://node1/rtc|apikey1|secret1,wss://node4/rtc|apikey2|secret2"
# Şimdilik tek node: LIVEKIT_NODES boş bırakılırsa mevcut LIVEKIT_URL kullanılır
livekit_nodes: str = ""

@property
def livekit_node_list(self) -> list[dict]:
    if not self.livekit_nodes:
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

Geriye dönük uyumlu: `LIVEKIT_NODES` boşsa mevcut `LIVEKIT_URL` kullanılır, hiçbir şey bozulmaz.

#### DB — Mirror Oda Tablosu

```sql
CREATE TABLE stream_mirror_rooms (
    id              SERIAL PRIMARY KEY,
    stream_id       INTEGER      NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    room_name       VARCHAR(120) NOT NULL UNIQUE,
    node_id         VARCHAR(50)  NOT NULL,
    livekit_url     TEXT         NOT NULL,
    is_primary      BOOLEAN      DEFAULT FALSE,
    viewer_count    INTEGER      DEFAULT 0,
    relay_egress_id TEXT,
    created_at      TIMESTAMPTZ  DEFAULT NOW()
);
CREATE INDEX ix_smr_stream_id ON stream_mirror_rooms(stream_id);
```

#### MirrorOrchestrator

`app/services/mirror_orchestrator.py`:

```python
MIRROR_THRESHOLD = 600   # Bu sayıyı geçince yeni mirror aç

class MirrorOrchestrator:

    async def get_join_node(self, stream_id: int) -> dict:
        """En az dolu LiveKit node'unu döner."""
        # Şimdilik: tek node → her zaman node1
        # Node4 eklenince: otomatik yük dengeleme devreye girer

    async def maybe_create_mirror(self, stream_id: int) -> None:
        """
        Viewer sayısı MIRROR_THRESHOLD'u geçtiyse
        ve kullanılmayan node varsa mirror oda açar + relay başlatır.
        ARQ worker task olarak çalışır.
        """

    async def get_viewer_counts(self, stream_id: int) -> dict[str, int]:
        """Redis key: live:viewer_count:{stream_id}:{node_id}"""
```

#### JoinStreamCommand Değişikliği

`app/use_cases/streams/commands/join_stream.py`:
```python
# Mevcut (hardcoded)
livekit_url = settings.livekit_url
room_name   = stream.room_name

# Yeni (orchestrator üzerinden)
node        = await mirror_orchestrator.get_join_node(stream.id)
livekit_url = node["url"]
room_name   = node["room_name"]
```

`JoinTokenOut` response yapısı değişmez — Flutter aynı JSON'u alır.

#### Webhook Handler

`app/routers/webhooks.py` — per-node viewer sayacı:
```
live:viewer_count:{stream_id}:node1  →  N     (yeni)
live:viewer_count:{stream_id}        →  N     (toplam — mevcut davranış korunur)
```

Flutter'a giden `viewer_count` WS eventi toplam sayıyı gösterir, mirror varlığı transparan.

#### Relay Bot (Mirror Oda Açılınca)

Mirror oda açılınca primary'den mirror'a video iletilir:

```python
# Seçenek A: LiveKit Egress API
async def start_relay(primary_room, mirror_room, from_node, to_node) -> str:
    # egress_id döner — stream sonunda durdurmak için saklanır

# Seçenek B: FFmpeg (Egress olmadan)
# ffmpeg -i rtmp://10.10.0.1/live/{room} -c copy -f rtmp rtmp://10.10.0.X/live/{mirror}
```

### 1.4 Flutter Tarafında Değişiklik Yok

`host_livekit_identity` = `str(host.id)` — relay bot bunu mirror odada da korur.  
Bid/chat WebSocket'leri `stream_id` bazlı çalışıyor — hangi LiveKit node'unda olunduğu fark etmez.

### 1.5 Faz 1 Sonucu

| | Faz 1 Öncesi | Faz 1 Sonrası |
|--|--------------|---------------|
| Maks. viewer (kod limiti) | 500 | 750 (tek node) |
| Yeni node eklenince | Kod değişikliği gerekir | Otomatik devreye girer |
| Flutter değişikliği | — | Yok |
| Donanım değişikliği | — | Yok |

**Tahmini süre:** 4–5 gün

---

## Faz 2 — mediasoup Geçişi

**Donanım değişikliği yok. Hâlâ aynı node'lar.**

### 2.1 Neden Önce Kod, Sonra Donanım?

LiveKit Mirror (Faz 1) ile yeni node eklenirse:

```
node1 → relay → node4
```

Video iki kez işlenir: node1 encode eder, node4'e relay edilir, node4 viewer'lara dağıtır.  
Bu relay overhead demek — hem bant genişliği hem CPU.

mediasoup PipeTransport ile yeni node eklenirse:

```
node1 ──PipeTransport(RTP tüneli)──► node4
```

RTP paketleri doğrudan tünellenir. Video sadece bir kez encode edilir.  
Yeni node eklemenin maliyeti sıfıra yakın.

**Sonuç: Önce mediasoup'a geç, sonra node ekle.**

### 2.2 mediasoup vs LiveKit

| | LiveKit OSS | mediasoup |
|--|-------------|-----------|
| Lisans | Apache 2.0 | **ISC — tam ticari özgür** |
| Dağıtık oda | ❌ Enterprise özelliği | ✅ PipeTransport |
| Relay overhead | Video kopyalanır | ❌ Yok — RTP tünellenir |
| Flutter SDK | ✅ Hazır | ❌ flutter_webrtc ile yazılır |
| Oda yönetimi | ✅ Dahili | ❌ Signaling server yazılır |
| CPU verimliliği | İyi | Çok iyi (C++ çekirdeği) |

### 2.3 PipeTransport — Gerçek Cascading

```
Yayıncı ──► Worker (node1)
                  │
       PipeTransport ← WireGuard mesh üzerinden RTP tüneli
                  │
          Worker (node4) ──► 700 viewer
                  │
       PipeTransport
                  │
          Worker (node5) ──► 700 viewer

Video encode: sadece 1 kez (yayıncı → node1)
Toplam: node sayısı × ~700 viewer @ 720p
```

### 2.4 Mimari

```
                    ┌──────────────────────────────────┐
                    │   Signaling Server (Node.js)     │
                    │   Her node'da çalışır            │
                    │   - Oda yönetimi                 │
                    │   - JWT auth (FastAPI shared)    │
                    │   - PipeTransport koordinasyonu  │
                    └─────────────┬────────────────────┘
                                  │ REST
                    ┌─────────────▼────────────────────┐
                    │        FastAPI (node1)            │
                    │   Bid · Chat · Analytics          │
                    └──────────────────────────────────┘
                                  │
          ┌───────────────────────┼──────────────────────┐
          ▼                       ▼                      ▼
   mediasoup (node1)       mediasoup (node4)      mediasoup (node5)
   Yayıncı + ~700 viewer   ~700 viewer            ~700 viewer
   WireGuard 10.10.0.1     10.10.0.5              10.10.0.6
```

### 2.5 Gerekli Geliştirmeler

#### Signaling Server (Node.js — yeni servis)

```
deploy/scale/V2.0/signaling/
├── server.js         ← Express + WebSocket
├── room_manager.js   ← Oda oluşturma, PipeTransport yönetimi
├── worker_pool.js    ← CPU core başı 1 mediasoup worker
└── package.json
```

Systemd servisi: `teqlif-signaling.service` — her node'da.

#### Flutter — flutter_webrtc

LiveKit Flutter SDK çıkar, `flutter_webrtc` paketi girer:

```dart
// Mevcut LiveKit SDK:
await room.connect(livekitUrl, token);

// Yeni mediasoup signaling WebSocket:
final ws = WebSocketChannel.connect(signalingUrl);
await _createRecvTransport(ws);
await _consumeTrack(ws, producerId: hostProducerId);
```

Tahminen 1–2 haftalık Flutter değişikliği.

#### FastAPI Adaptör Katmanı

- `make_livekit_token()` → `make_signaling_token()`
- `JoinTokenOut.livekit_url` → `signaling_url`
- Webhook handler → mediasoup event formatına uyarlanır
- Co-host → mediasoup `updateProducerPermissions`

#### Feature Flag — Sıfır Kesintili Geçiş

```python
# config.py
sfu_backend: str = "livekit"  # "livekit" veya "mediasoup"
```

Staging'de mediasoup açık, production'da LiveKit — test yeterince tamamlanınca tek satırla production geçişi. Geri dönüş yine tek satır.

### 2.6 Faz 2 Sonucu

| | Faz 2 Öncesi | Faz 2 Sonrası |
|--|--------------|---------------|
| Cascading | Relay (video kopyalanır) | PipeTransport (RTP tüneli) |
| Yeni node overhead | Yüksek | Sıfıra yakın |
| Flutter SDK | LiveKit SDK | flutter_webrtc |
| Lisans kısıtı | Apache 2.0 | ISC — tam özgür |

**Tahmini süre:** 4–5 hafta

---

## Faz 3 — Yeni Node'larla Kapasite Artırımı

**Yazılım hazır. Artık her yeni node tam verimle çalışır.**

### 3.1 Hangi Node Eklenebilir?

| Kriter | Gereksinim | Neden |
|--------|-----------|-------|
| Bant genişliği | **2 Gbps / unmetered** | 720p'de ~700 viewer; throttle riski yok |
| CPU | ≥ 4 çekirdek | SRTP/DTLS şifreleme yükü |
| RAM | ≥ 8 GB | mediasoup worker havuzu |
| Ağ | WireGuard peer olabilmeli | PipeTransport mesh üzerinden çalışır |
| Referans | node1 (OVHcloud Limburg) | Kanıtlanmış spec |

**Neden node3-tipi değil:**  
33TB/ay bant genişliği cap → yoğun streaming'de throttle riski.  
Production streaming için unmetered zorunlu.

### 3.2 Kapasite Hesabı

Her yeni node1-eşdeğeri PipeTransport sayesinde:

| Node sayısı | 720p kapasitesi | 480p kapasitesi |
|-------------|-----------------|-----------------|
| 1 (mevcut) | ~700 viewer | ~2000 viewer |
| 2 | ~1400 viewer | ~4000 viewer |
| 3 | ~2100 viewer | ~6000 viewer |
| N | ~N × 700 viewer | ~N × 2000 viewer |

### 3.3 Yeni Node Deploy Adımları

Faz 2 tamamlandıktan sonra node4 eklemek için:

1. `deploy/scale/resources/node4/` oluştur (node1 temel alınarak)
2. `bootstrap_node4.sh` — LiveKit yerine mediasoup + signaling server
3. WireGuard mesh'e ekle (10.10.0.5)
4. `LIVEKIT_NODES` yerine signaling server URL listesine ekle
5. Prometheus scrape ekle (node3 prometheus.yml)
6. `MirrorOrchestrator` yeni node'u otomatik tanır — kod değişikliği gerekmez

---

## Yol Haritası

```
Şimdi           Faz 1           Faz 2           Faz 3
   │            (4-5 gün)       (4-5 hafta)     (ihtiyaç halinde)
   │               │               │               │
   ▼               ▼               ▼               ▼
Tek node       Yazılımsal      mediasoup       Yeni node'lar
node1          iyileştirme     geçişi          (node4, node5...)
500 viewer     750 viewer      PipeTransport   N × 700 viewer
(livekit.yaml  (aynı donanım)  (aynı donanım)  (tam verimli)
 hard limit)   multi-node      sıfır overhead  ölçekleme
               kod hazır       Flutter yeni SDK
```

---

## Kilometre Taşları

**KT-1 (Faz 1 tamamlandı):**
- [ ] `livekit.yaml` max_participants 750'ye yükseltildi — node1'e deploy edildi
- [ ] `stream_mirror_rooms` tablosu + alembic migration aktif
- [ ] `MirrorOrchestrator` çalışıyor — tek node, multi-node hazır
- [ ] `JoinStreamCommand` orchestrator kullanıyor
- [ ] Webhook per-node viewer count aktif
- [ ] Relay bot hazır (tetikleyici: 600+ viewer)
- [ ] Flutter değişikliği yok — test edildi
- [ ] Kod: `LIVEKIT_NODES` env var tanımlandı, boş bırakılınca mevcut node kullanılır

**KT-2 (Faz 2 — staging):**
- [ ] mediasoup signaling server node3 staging'de çalışıyor
- [ ] Flutter flutter_webrtc ile staging'e bağlanabiliyor
- [ ] `sfu_backend=mediasoup` staging'de aktif
- [ ] Bid/chat staging'de aynı şekilde çalışıyor
- [ ] PipeTransport ile node1 ↔ node3 cascading test edildi (staging izin verdiği ölçüde)

**KT-3 (Faz 2 — production):**
- [ ] `sfu_backend=mediasoup` production'da aktif
- [ ] LiveKit servisleri standby'da (kaldırılmadı — geri dönüş için)
- [ ] node1 tek başına mediasoup ile stabil çalışıyor

**KT-4 (Faz 3 — ilk yeni node):**
- [ ] node4 kuruldu (node1-eşdeğeri, 2Gbps/unmetered)
- [ ] WireGuard mesh'e eklendi
- [ ] mediasoup PipeTransport node1 ↔ node4 aktif
- [ ] `MirrorOrchestrator` node4'ü otomatik kullanıyor
- [ ] Kapasite testi: ~1400 viewer @ 720p

---

## Kararlar ve Gerekçeler

| Karar | Gerekçe |
|-------|---------|
| Faz sırası: kod → mediasoup → donanım | Donanımı mediasoup'tan önce eklemek relay overhead yaratır |
| Faz 1'de donanım değişikliği yok | Yazılımsal dar boğazlar giderilmeden donanım eklemek verimsiz |
| Faz 1 geriye dönük uyumlu | `LIVEKIT_NODES` boşsa mevcut davranış korunur — sıfır risk |
| max_participants 500→750 | node1 donanım kapasitesine göre; hemen uygulanabilir |
| mediasoup ISC lisansı | Ticari kullanım için tam özgür; LiveKit Enterprise kısıtı yok |
| PipeTransport önce, donanım sonra | Her yeni node sıfır overhead ile havuza katılır |
| node3/node2 production mirror'dan dışarıda | node3 bandwidth cap, node2 shared — unmetered zorunlu |
| Flutter değişikliği Faz 2'de | Faz 1 risk-free; Flutter büyük değişiklik Faz 2'ye ertelendi |
