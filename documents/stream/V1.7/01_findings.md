# Stream V1.7 — Çok-Node Fan-out Araştırması

Tarih: 2026-10-20

---

## 1. Mevcut Durum (As-Is)

### Yayın Yaşam Döngüsü

1. `start_stream.py` → `orchestrator.allocate_node(ServiceType.MEDIA)` çağrısı yapar
2. Orchestrator Redis'teki `edge:metrics:*` anahtarlarından CPU + katılımcı sayısına göre en uygun node'u seçer
3. `livekit_url` veritabanına **tek bir string** olarak yazılır
4. `join_stream.py` her izleyiciye `stream.livekit_url`'i döner — tüm izleyiciler aynı node'a gider

### Darboğaz

Tek yayın = tek node. Bir odanın tüm izleyicileri aynı node'un NIC'inden çıkar.
Tavan: node3 veya node4'ün 2 Gbps portu → güvenli ~750 izleyici @ 720p 30fps (≈2.2 Mbps/izleyici).

### Altyapı (İlgili)

| Özellik | Değer |
|---------|-------|
| node3 | 2 Gbps, OVH Frankfurt |
| node4 | 2 Gbps, OVH Frankfurt, 6 vCPU Haswell |
| node3 ↔ node4 ping | < 0.8 ms (WireGuard, aynı DC) |
| LiveKit Redis | `127.0.0.1:6379` → HAProxy → `10.10.0.1:6379 DB:1` (her iki node'da aynı) |
| LiveKit API key | `teqlif_livekit_key` — node3 ve node4'te aynı |
| Chat / Bid | FastAPI WebSocket (node1) — LiveKit'ten tamamen bağımsız |
| `net_tx_mbps` | `health.py:310-330` `_net_mbps()` + `edge_metrics_agent.py:419` — Redis `edge:metrics:{node_id}`'e her 5 saniyede yazılıyor |

---

## 2. LiveKit Clustering Kısıtı

**Room-Node Pinning**: Açık kaynak LiveKit'te bir oda bütünüyle tek bir sunucuya bağlıdır.

Node3 ve node4 aynı Redis ve aynı API key paylaşsa da bir izleyiciyi node4'e yönlendirmek medyayı node4'ten dağıtmaz. Node4 sinyali node3'e proxy eder; ICE candidate olarak node3'ün IP'sini döner. UDP paketleri fiziksel olarak yine node3'ten akar.

> *"An individual room must fit entirely on a single node."* — LiveKit resmi dokümantasyonu

### Multi-Room vs Tek Büyük Yayın

| Senaryo | Mevcut Durum |
|---------|-------------|
| 10 yayın, her birinde 150 izleyici | Orchestrator yayınları node'lara dengeli dağıtıyor — sorun yok |
| 1 yayın, 750+ izleyici | Source node portu doyar — relay gerekli |

---

## 3. Transcoding Gerçeği

`livekit_subscriber.py` incelemesinden: livekit.rtc Python SDK'sı gelen VP8 paketlerini ham piksellere (BGRA/I420) decode eder; publish ederken libvpx ile sıfırdan encode eder. Bu tam bir **software transcoding** işlemidir.

| | Değer |
|--|-------|
| 720p 30fps relay CPU | 1 core'un ~%25–35'i |
| node4 toplam kapasite | 6 vCPU |
| Tek relay etkisi | Toplam kapasitenin ~%5'i |
| 5 eşzamanlı relay | ~2 tam core |

---

## 4. Hedef Mimari

### Tasarım İlkesi: Node Sayısından Bağımsız (Generic)

Tüm implementasyon kaç streaming node olduğundan bağımsız çalışır. Hardcode node adı, hardcode suffix yoktur.

- 1 node (staging): relay candidates boş → relay devreye girmez, sistem çalışmaya devam eder
- 2 node (prod): source node dolunca diğer node relay olur
- N node: her node hem source hem relay candidate olabilir

`all_media_nodes()` kaç node varsa hepsini döner. Relay mantığı bu listeyi kullanır:

```python
relay_candidates = [n for n in all_media_nodes() if n["node_id"] != source_node_id]
if not relay_candidates:
    return  # tek node, relay mümkün değil — sessizce pas geç
```

Relay oda adı generic:
```python
relay_room = f"{room_name}_relay_{target_node_id}"
# Örnek: "abc123_relay_node4"
```

### Strateji: On-Demand Relay

Relay her yayında çalışmaz. Bir node'un `net_tx_mbps` değeri (Redis `edge:metrics:{node_id}`'den okunur — zaten canlı akan metrik) eşiği aştığında tetiklenir.

Tetikleme ve kapatma eşikleri `cluster.yaml`'da tanımlanır — `recording:` ile kardeş seviyede `relay:` bloğu olarak (mevcut yapıyla tutarlı, agent her 60s yeniden okur):

```yaml
# cluster.yaml — mevcut recording: bloğunun yanına eklenir
relay:
  enabled: true
  tx_threshold_mbps: 800       # 2 Gbps portun %40'ında relay tetiklenir
  min_viewers_teardown: 100    # Toplam izleyici bu sayının altına inince relay kapanır
  heartbeat_interval_sec: 10   # Redis ready TTL tazeleme aralığı
  ready_ttl_sec: 30            # Redis ready anahtarı TTL
```

Python koduna eşik değeri hardcode edilmez; agent döngüsü cluster.yaml'ı her cycle'da okur — `recording:` bloğunun okunma mekanizmasıyla aynı.

```
Yayıncı → source_node (SFU, oda: room_name)
                ↓ WireGuard ~2.2 Mbps (tek akış)
           relay_node (Relay agent, oda: room_name_relay_node_id)
                ↓
          ~800 izleyici × 2.2 Mbps

source_node → ~800 izleyici + 1 relay bağlantısı ≈ 1.76 Gbps
relay_node  → ~800 izleyici                       ≈ 1.76 Gbps
Toplam çıkış: ~3.5 Gbps
```

### Relay Konumu

Relay, teqlif-agent altında **her streaming node'unda** yaşar — tıpkı recorder.py'nin livekit_subscriber.py'ı yönetmesi gibi. Relay her zaman **alıcı/dağıtıcı node'da** çalışır, dolmuş node'da değil.

Node1 relay için uygun değildir: ana API + PostgreSQL + Redis servisleri çalıştırmaktadır; transcoding yükü API servisini etkileyebilir ve source_node→node1→relay_node gereksiz ağ hop'u ekler.

### Koordinasyon Akışı

İki ayrı Redis anahtarı kullanılır:
- `live:relay:needed:{room}` → relay agent okur, süreci başlatır; join_stream.py bu anahtarı **okumaz**
- `live:relay:ready:{room}` → **30 saniye TTL ile** yazılır; relay süreci canlı olduğu sürece her `heartbeat_interval_sec` saniyede `EXPIRE 30` ile tazeler; relay çökerse 30 saniye içinde otomatik silinir, EdgeOrchestrator tüm trafiği source_node'a çeker

Redis payload tam JSON kontratı:
```json
{"relay_node_id": "node4", "livekit_url": "https://stream4.teqlif.com", "relay_room": "uuid_relay_node4"}
```

Acil fren (kill switch): `teqlif:relay:emergency_disabled` Redis anahtarı set edilirse EdgeOrchestrator relay kontrolünü pas geçer, RelayManager tüm relay subprocess'lerini kapatır. Deployment gerektirmez:
```bash
redis-cli -h 10.10.0.1 -a <pass> SET teqlif:relay:emergency_disabled 1 EX 3600
```

```
1. Yayın başlar → orchestrator en uygun node'u seçer (mevcut davranış)
2. İzleyiciler gelir → hepsi source_node'a gider (mevcut davranış)
3. source_node agent:
   net_tx_mbps > tx_threshold_mbps koşulu 15s kesintisiz sağlanmalıdır (sustained window —
   anlık spike relay başlatmamalı). Ayrıca relay_node'un CPU < %70 ve
   net_tx_mbps < 600 Mbps olduğu doğrulanır (çift taraflı kilitlenme engeli).
   → teqlif:relay:emergency_disabled varsa pas geç
   → relay_candidates = all_media_nodes() - source_node
   → en az yüklü relay_node seçilir
   → Redis'e yazar: live:relay:needed:{room} = relay_node_id
4. relay_node agent: live:relay:needed:{room} anahtarını okur
   → relay.py → livekit_relay.py başlatır (start_new_session=True, nice -n -5)
   → source_node'a ws://{source_wg_ip}:7880 üzerinden bağlanır
   → relay_room = f"{room_name}_relay_{relay_node_id}" odasını açar
   → ilk video keyframe'i relay_room'a bastıktan sonra:
      Redis'e yazar: live:relay:ready:{room} = JSON payload (TTL=30s)
      Heartbeat döngüsü her 10s'de EXPIRE 30 ile TTL'i tazeler
5. EdgeOrchestrator.resolve_stream_endpoint(stream):
   → teqlif:relay:emergency_disabled varsa source_node döner
   → live:relay:ready:{room} var mı?
   → yoksa: source_node endpoint döner (warmup süresinde siyah ekran yok)
   → varsa: source_node ve relay_node arasında net_tx_mbps yüküne göre en dengeli endpoint seçilir
   → StreamEndpoint(livekit_url, room_name, node_id) döner
   join_stream.py: endpoint = await orchestrator.resolve_stream_endpoint(stream)
                  token = make_livekit_token(endpoint.room_name, user, can_publish=False)
                  node_url = endpoint.livekit_url
6. Relay kapanma koşulları (sadece):
   → Yayın sona erdiğinde (StreamEndedEvent / webhook)
   → Her iki node'daki toplam izleyici < cluster.yaml:min_viewers_teardown olduğunda
   net_tx_mbps düştü diye relay KAPATILMAZ — source_node trafiği relay devredeyken
   doğal olarak düşer; bu beklenen davranıştır
7. Relay çökerse (_reap_finished):
   → RelayManager subprocess çıkış kodunu gördüğü an DEL live:relay:ready:{room} çalıştırır
   → LiveKit API üzerinden relay_room odasını sonlandırır (izleyiciler yeniden bağlanır)
   → Circuit breaker: 10 dakika içinde 2'den fazla yeniden başlatma girişiminde o yayın
     için relay blacklist'e alınır, Telegram'a alarm düşülür, source_node ile devam edilir
8. Relay kapandığında (normal):
   → live:relay:needed:{room} ve live:relay:ready:{room} silinir
   → EdgeOrchestrator tüm yeni izleyicileri source_node'a döner
```

### Relay Durum Makinesi (State Machine)

```
[IDLE]
  │  source_node: net_tx_mbps > tx_threshold_mbps kesintisiz 15s
  │  + relay_node CPU < %70 ve tx < 600 Mbps
  │  + teqlif:relay:emergency_disabled yok
  ▼
[REQUESTED] ──→ Redis: live:relay:needed:{room}  (TTL: 60s)
  │  relay_node agent anahtarı okur, livekit_relay.py subprocess başlatır
  ▼
[WARMING_UP] ──→ WebRTC handshake + ilk keyframe decode/encode (~1.5–2s)
  │  Bu aşamada tüm izleyiciler source_node'a gitmeye devam eder
  │  (siyah ekran yok)
  │  İlk keyframe relay_room'a basıldı
  ▼
[ACTIVE] ──→ Redis: live:relay:ready:{room}  (TTL: 30s, 10s heartbeat ile EXPIRE 30)
  │  EdgeOrchestrator izleyicileri source_node / relay_node arasında
  │  net_tx_mbps yüküne göre dengeli dağıtır
  │  relay crash → _reap_finished → [IDLE] (circuit breaker sayar)
  │  Yayın bitti VEYA toplam izleyici < min_viewers_teardown
  ▼
[TEARING_DOWN] ──→ live:relay:needed:{room} + live:relay:ready:{room} silinir
  │  livekit_relay.py SIGTERM → SIGKILL
  │  LiveKit API: relay_room kapatılır
  ▼
[IDLE]
```

### Orphan Process Kurtarma

`recorder.py:187`'deki `_recover_orphaned()` pattern'ına sadık kalarak RelayManager başlangıcında kendi PID havuzunda olmayan eski `livekit_relay.py` süreçleri taranır ve `SIGTERM → SIGKILL` ile temizlenir. Tüm subprocess'ler `start_new_session=True` ile başlatılır (process group üzerinden temiz kapanma).

### Observability

nodeMonitor izlemesi için standart metrikler:

| Metrik | Açıklama |
|--------|----------|
| `teqlif_stream_relay_status{room,source,target}` | 0=inactive, 1=warming_up, 2=active |
| `teqlif_stream_relay_fps{room}` | Relay odasına basılan video FPS |
| `teqlif_stream_relay_restart_count{room}` | Circuit breaker sayacı |

Telegram alarm kuralları:
- `relay_active == 1` iken `source_tx + target_tx > 3200 Mbps` → **CRITICAL: Media cluster capacity warning**
- `relay_restart_count > 2` → **WARNING: Stream relay flapping**

### Değişmeyen Şeyler

- Chat ve bid WebSocket — LiveKit'ten bağımsız, etkilenmez
- `live_streams.livekit_url` kolonu — değişmez, source node URL'sini tutar
- `live_streams` tablosuna `source_node_id VARCHAR(50) nullable` eklenir

---

## 5. Stream Recording Mimarisi

### Temel Kural

Kayıt her zaman ve yalnızca `source_node` üzerinde yapılır. Relay node ve relay odaları (`room_relay_*`) asla kaydedilmez.

Gerekçe:
- **Kalite**: source_node'daki akış yayıncının telefonundan gelen orijinal VP8'dir. relay_node'daki akış zaten bir kez decode/encode edilmiş ikincil kopyadır — kayıt kalitesi düşer.
- **Zaman bütünlüğü**: Relay on-demand devreye girer (örn. yayının 15. dakikasında). relay_node'da kayıt başlasaydı ilk 15 dakika kayıtta yoktu. source_node yayının 0. saniyesinden itibaren oradadır.
- **CPU izolasyonu**: relay_node zaten transcoding yapar (~%30 core). Kayıt I/O'su source_node'da kalınca iki node dengeli iş bölümü yapar.

### Mevcut Açık (Phantom Recorder)

`lifecycle_commands.py:22` — `teqlif:recording:stream_started` pub/sub payload'ında `source_node_id` yok:

```python
# Mevcut (eksik):
payload = json.dumps({"stream_id": stream_id, "room_name": room_name, "host_id": host_id})
```

Tüm media node'larındaki `recorder.py` bu eventi alır ve her biri `ws://127.0.0.1:7880`'e bağlanmayı dener. source_node başarılı olur; diğer node'lar odayı bulamaz, 5 dakika boşta bekleyip timeout olur (phantom recorder). Şu an veri kaybı yok ama kaynak israfı ve log kirliliği var. Relay devreye girince relay odasıyla karışıklık riski artar.

### Düzeltme

`start_stream.py`'ın seçtiği node'un `node_id`'si stream tablosuna ve recording event payload'una eklenir:

```python
# lifecycle_commands.py — düzeltilmiş:
payload = json.dumps({
    "stream_id": stream_id,
    "room_name": room_name,
    "host_id": host_id,
    "source_node_id": stream.source_node_id,
})
```

```python
# recorder.py _drain_event_queue — tek satır koruma:
if data.get("source_node_id") and data["source_node_id"] != self._cfg.node_id:
    return  # bu yayın bu node'da değil, kaydetme
```

`recorder.py` fallback poll sorgusu backward compatibility için `source_node_id IS NULL` koşulunu içerir — mevcut kayıtlar bu alan olmadan oluşturulmuştur:

```sql
WHERE ls.status = 'live'
  AND (ls.source_node_id = $1 OR ls.source_node_id IS NULL)
```

### Relay ile Birlikte Tam Kayıt Akışı

```
t=0   Yayıncı → source_node (WebRTC)
      source_node agent → livekit_subscriber.py başlatır → MKV yazar

t=X   net_tx_mbps > 800 → relay_node devreye girer
      relay_node: izleyicilere video basar, KAYIT BAŞLATMAZ

t=Son Yayıncı yayını bitirir
      livekit_subscriber.py → MKV kapatır
      relay_node → relay kapanır, diskte çöp bırakmaz
      EncoderManager → MKV → MP4 encode (source_node)
      MinIO → upload
      cleaner.py → ham MKV siler
```

### Tespit Edilen Kritik Hatalar

Kod incelemesinde (2026-10-21) recorder/relay mimarisinde 6 sorun doğrulandı.

#### H1 — KRITIK: Orchestrator Fallback → Kayıt Tamamen Kaçırılıyor

**Konum**: `backend/app/services/edge_orchestrator.py:145-158`

```python
# Mevcut hatalı hali:
def _fallback(self) -> dict:
    return {"node_id": "fallback", "livekit_url": settings.edge_livekit_urls[0]}
```

`recorder.py` kayıt öncesi şu kontrolü yapar:

```python
if data.get("source_node_id") and data["source_node_id"] != self._cfg.node_id:
    return  # bu yayın bu node'da değil
```

`source_node_id = "fallback"` olduğunda ne node3 ne node4 bu koşulu geçer; **hiçbir recorder kayıt başlatmaz**. Yayıncı yayını bitirir, kayıt yok.

**Düzeltme**: `_fallback()` imzası korunur (`service_type: ServiceType` parametresi kaldırılmaz); MEDIA için gerçek node_id URL→node eşleştirmesiyle türetilir. `config.py`'a `edge_livekit_node_map: dict[str, str] = {}` eklenir (key=livekit_url, value=node_id):

```python
# config.py — yeni alan:
edge_livekit_node_map: dict[str, str] = {}
# Ortam değişkeni: EDGE_LIVEKIT_NODE_MAP={"wss://live.node3.teqlif.com":"node3",...}

# edge_orchestrator.py — _fallback() düzeltmesi:
def _fallback(self, service_type: ServiceType) -> Dict[str, Any]:
    node: Dict[str, Any] = {
        "node_id":     "fallback",
        "livekit_url":  "",
        "minio_url":    "",
        "ai_proxy_url": "",
    }
    if service_type == ServiceType.MEDIA:
        url = settings.edge_livekit_urls[0] if settings.edge_livekit_urls else ""
        node["livekit_url"] = url
        node["node_id"]     = settings.edge_livekit_node_map.get(url, "fallback")
    elif service_type == ServiceType.STORAGE:
        node["minio_url"] = settings.edge_minio_urls[0] if settings.edge_minio_urls else ""
    elif service_type == ServiceType.AI:
        node["ai_proxy_url"] = settings.ai_proxy_url
    return node
```

Alternatif savunma katmanı olarak `recorder.py`'de:

```python
# source_node_id bilinmiyorsa veya "fallback" ise URL'den eşleştir
if data.get("source_node_id") in (None, "fallback"):
    # livekit_url bu node'un URL'siyle örtüşüyor mu?
    if data.get("livekit_url") != self._cfg.livekit_url:
        return
```

---

#### H2 — KRITIK: Erken Kapanma — Host Yeniden Bağlanmasında Kayıt Duruyor

**Konum**: `deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py:336-341`

```python
@room.on("participant_disconnected")
def on_participant_disconnected(participant):
    if not room.remote_participants:   # BUG: tüm izleyiciler relay_node'daysa
        stop_evt.set()                 # bu sayaç 0 olur; kayıt duruyor
```

**İki ayrı hata, biri gizli:**

1. `remote_participants` boşluk kontrolü relay senaryosunda bozuluyor: izleyiciler `relay_room`'dadır; `source_room` boş görünür → kayıt durur.
2. Host identity kontrolüne geçilse bile aynı sorun devam eder — **daha ince fakat daha tehlikeli**: Backend `webhooks.py:69`'da `_HOST_GRACE_SECONDS = 120` (2 dakika) grace period uygular; host 120 saniyeye kadar dönerse yayın kapatılmaz. Ancak `livekit_subscriber.py` host ayrıldığı an `stop_evt.set()` yaparsa kayıt ölür, backend yayını açık tutar, **yayının ikinci yarısı hiç kaydedilmez**.

**Düzeltme**: `livekit_subscriber.py`'a backend grace period'ıyla eşleşen **recording grace timer**:

```python
_host_grace_task: asyncio.Task | None = None

@room.on("participant_disconnected")
def on_participant_disconnected(participant):
    nonlocal _host_grace_task
    # Sadece host koptuğunda grace timer başlat — izleyici/relay ayrılması kaydı etkilemez
    if participant.identity != cfg.host_identity:
        return
    logger.warning("Host ayrıldı, %ds recording grace başlatılıyor | room=%s",
                   cfg.recording_grace_seconds, cfg.room_name)
    _host_grace_task = asyncio.create_task(_host_grace_timer())

@room.on("participant_connected")
def on_participant_connected(participant):
    nonlocal _host_grace_task
    if participant.identity == cfg.host_identity and _host_grace_task:
        _host_grace_task.cancel()
        _host_grace_task = None
        logger.info("Host grace içinde döndü — kayıt devam ediyor | room=%s", cfg.room_name)

async def _host_grace_timer():
    await asyncio.sleep(cfg.recording_grace_seconds)
    logger.warning("Host grace süresi doldu — kayıt sonlandırılıyor | room=%s", cfg.room_name)
    stop_evt.set()
```

`cfg.recording_grace_seconds` değeri `cluster.yaml`'dan okunur:

```yaml
# cluster.yaml — recording: bloğuna eklenir
recording:
  recording_grace_seconds: 120   # webhooks.py:_HOST_GRACE_SECONDS ile eşleşmeli
```

`recording_grace_seconds` her zaman `_HOST_GRACE_SECONDS` (120s) değerine **eşit veya büyük** olmalıdır; grace timer backend'in yayını açık tuttuğu süreyi aşmadan sona ererse kayıt ölür, yayının ikinci yarısı kaydedilmez. Grace timer birincil kapanma sinyali değil son güvencedir: LiveKit `roomDeleted` disconnect reason geldiğinde `stop_evt` zaten tetiklenir, timer o ana kadar aktifse iptal edilir.

---

#### H3 — YÜKSEK: Relay Dynacast — Video Kalite Seçimi Eksik

**Konum**: `deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py:331` (kayıt tarafında mevcut, relay tarafında eksik)

`livekit_subscriber.py` recorder açıkça HIGH kalite talep eder:

```python
publication.set_video_quality(rtc.VideoQuality.VIDEO_QUALITY_HIGH)
```

Yeni yazılacak `livekit_relay.py` subscriber tarafında aynı çağrıyı yapmak **zorundadır**; aksi hâlde LiveKit Dynacast düşük katmana düşer:

```python
# livekit_relay.py — on_track_subscribed:
if track.kind == rtc.TrackKind.KIND_VIDEO:
    publication.set_video_quality(rtc.VideoQuality.VIDEO_QUALITY_HIGH)
```

---

#### H4 — YÜKSEK: Disk I/O Çakışması — FFmpeg ve MKV Eş Zamanlı Yazma

**Konum**: `deploy/scale/V2.1/teqlif-agent/modules/encoder.py` (FFmpeg subprocess başlatma)

`livekit_subscriber.py` yayın süresince MKV'ye aktif yazar; `encoder.py` tamamlanan bir önceki yayının MKV'sini aynı anda encode eder. Her iki süreç de aynı disk I/O bandını kullanır. FFmpeg encode yük altında (~%60 vCPU) sırasında MKV yazma gecikmesi → frame drop → kayıt bozulması riski.

**Düzeltme**: FFmpeg subprocess `ionice -c 3` (idle I/O class) ile başlatılır:

```python
# encoder.py — subprocess başlatma:
cmd = ["ionice", "-c", "3", "ffmpeg", "-y", "-i", str(mkv_path), ...]
```

`nice -n 19` zaten uygulanıyorsa `ionice` bağımsız eklenir; ikisi birlikte çalışır.

---

#### H5 — ORTA: Webhook Kirliliği — Relay Odası Filtrelenmiyor

**Konum**: `backend/app/routers/webhooks.py:52-54`

```python
if event_type == "room_finished" and room_name:
    background_tasks.add_task(_on_call_room_finished, room_name)
```

Relay odası (`abc123_relay_node4`) kapandığında `room_finished` webhook'u tetiklenir. `_on_call_room_finished` bu oda adıyla çalıştırılır, DB'de karşılık bulamaz, sessizce hata verir/log kirliliği bırakır. Relay oda adları `_relay_` token'ı içerdiğinden basit bir filtre yeterlidir:

```python
if event_type == "room_finished" and room_name:
    if "_relay_" in room_name:
        logger.debug("LiveKit webhook: relay odası kapandı, atlanıyor | room=%s", room_name)
        return
    background_tasks.add_task(_on_call_room_finished, room_name)
```

---

#### H6 — ORTA: İlk Kare Gecikmesi SLA

**Gözlem**: Warm relay subprocess'i relay_room'a ilk kareyi bastıktan sonra `live:relay:ready:{room}` yazılır. WebRTC DTLS + ICE handshake + ilk keyframe decode/encode süresi **1.5–3s** arasındadır. Soğuk başlatmada (fresh subprocess) bu süre **3–5s**'ye çıkabilir.

**SLA**: `WARMING_UP → ACTIVE` geçiş süresi ≤ **3s** (warm), ≤ **5s** (cold). Bu pencerede tüm izleyiciler source_node'da kalmaya devam eder; visible artifact yok.

İzleme: `relay.py` WARMING_UP başlangıç timestamp'ini kaydeder; ACTIVE geçişinde `teqlif_stream_relay_warmup_seconds{room}` Prometheus metriği yazılır. > 5s ise Telegram uyarısı düşülür.

---

### Node Crash Kurtarma — Kural 1: Salvage to Encoding

**Temel prensip**: MKV container cluster tabanlıdır (ADR §19). Elektrik fişi çekilse bile son saniyeye kadar yazılmış kareler FFmpeg tarafından sorunsuzca okunabilir. Bu avantajı kullanmak gerekir.

**Mevcut problem** ([recorder.py:196-201](deploy/scale/V2.1/teqlif-agent/modules/recorder.py#L196)): Tüm `status='recording'` kayıtlar blanket `failed` yapılıyor — diskteki MKV çöpe gidiyor.

**Yeni `_recover_orphaned()` mantığı**:

```python
async def _recover_orphaned(self, dsn: str) -> None:
    """Agent yeniden başladığında yarım kalan MKV'leri kurtarır (Salvage)."""
    conn = await asyncpg.connect(dsn=dsn)
    rows = await conn.fetch(
        "SELECT id, raw_path FROM stream_recordings "
        "WHERE status = 'recording' AND recording_node = $1",
        self._cfg.node_id,
    )
    for row in rows:
        raw_file = Path(row["raw_path"]) if row["raw_path"] else None
        if raw_file and raw_file.exists() and raw_file.stat().st_size > 100_000:
            await conn.execute(
                """UPDATE stream_recordings
                   SET status = 'encoding',
                       error_message = 'node crash: kısmi kurtarıldı (salvaged)',
                       updated_at = NOW()
                   WHERE id = $1""",
                row["id"],
            )
            logger.info("Orphan kayıt kurtarıldı → encoding: rec_id=%d size=%.1fMB",
                        row["id"], raw_file.stat().st_size / 1_000_000)
        else:
            await conn.execute(
                "UPDATE stream_recordings SET status='failed', "
                "error_message=$1, updated_at=NOW() WHERE id=$2",
                "node crash: dosya yok/boş", row["id"],
            )
    await conn.close()
```

Eşik `100_000 bytes` (100KB): 2 saniyelik 720p kayıt bile kurtarmaya değer; altındakiler gerçekten bozuk/boş dosyayı işaret eder. `EncoderManager`, `status='encoding'` olan kaydı normal akışta alır, MP4'e çevirir, MinIO'ya yükler.

---

### Node Crash Sonrası — Kural 2: Ghost Stream Prevention

**Problem**: Node3 boot eder. `_sync_recordings()` DB'de `status='live'` olan yayınları tarar. DB hâlâ `live` ama LiveKit odası yok. `_sync_recordings()` boş odaya yeni subscriber başlatır (ghost recorder).

Kural 1 bu senaryonun büyük bölümünü kapatır: mevcut recording satırı `encoding`'e çekilir; `_sync_recordings()` NOT EXISTS koşulunda bunu görür. Kalan kenar durum: crash, recording satırı oluşturulmadan önce gerçekleştiyse. LiveKit ListRooms kontrolü ek güvence sağlar.

`_purge_ghost_streams()` — `_recover_orphaned()` ile `_sync_recordings()` arasına eklenir:

```python
async def _purge_ghost_streams(self, dsn: str, svc_cfg: dict) -> None:
    """Reboot sonrası LiveKit'te fiziksel olarak bulunmayan 'live' yayınları kapatır."""
    ws_url     = svc_cfg.get("livekit_ws_url") or "ws://127.0.0.1:7880"
    http_url   = ws_url.replace("ws://", "http://").replace("wss://", "https://")
    api_key    = os.environ.get("LIVEKIT_API_KEY", "")
    api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
    try:
        from livekit.api import LiveKitAPI, ListRoomsRequest
        async with LiveKitAPI(url=http_url, api_key=api_key, api_secret=api_secret) as api:
            resp = await api.room.list_rooms(ListRoomsRequest())
        active_rooms = {r.name for r in resp.rooms}
    except Exception as exc:
        logger.warning("LiveKit ListRooms başarısız, ghost purge atlandı: %s", exc)
        return   # güvenli fallback — yayınlara dokunma

    conn = await asyncpg.connect(dsn=dsn)
    stale = await conn.fetch(
        "SELECT id, room_name FROM live_streams "
        "WHERE status = 'live' AND source_node_id = $1",
        self._cfg.node_id,
    )
    for row in stale:
        if row["room_name"] not in active_rooms:
            await conn.execute(
                "UPDATE live_streams "
                "SET status='ended', is_live=false, ended_at=NOW() "
                "WHERE id=$1",
                row["id"],
            )
            logger.warning("Ghost stream kapatıldı: stream_id=%d room=%s",
                           row["id"], row["room_name"])
    await conn.close()
```

Çağrı sırası (`recorder.py` init bloğu):

```
_recover_orphaned()     # 1. MKV varsa encoding'e al
_purge_ghost_streams()  # 2. LiveKit boş → stale streams → ended
_initialized = True
_sync_recordings()      # 3. Artık ghost recorder oluşmaz
```

`livekit.api` paketi zaten kurulu. Metot yalnızca `self._cfg.node_id`'e ait stream'lere dokunur.

---

### Multi-Node Failover — Kural 3

Node3 çöktüğünde yayıncı yayını kaybetmeden node4'ten devam eder. `stream_recordings` tablosunda `stream_id` UNIQUE değil (sadece index), iki parça kaydı zaten destekleniyor.

#### Komple Akış

```
node3 çöker
   │
   ▼  HostStreamViewModel
RoomDisconnectedEvent → scheduleReconnect()
   │  7 deneme × backoff  (2+4+8+16+30+30+30 = ~120s)
   │  Her denemede: connect(node3_url) → başarısız
   │
   ▼  _reconnectAttempts >= _kMaxReconnectAttempts
_tryFailover()
   │
   ├─→ POST /api/streams/{id}/failover
   │     ├─ stream.status == 'live'?          ✓
   │     ├─ caller == stream.host_id?         ✓
   │     ├─ is_node_healthy(node3) == False?  ✓  (edge:metrics stale)
   │     ├─ failover rate limit (5dk/stream)  ✓
   │     ├─ allocate_node(exclude=node3)  →  node4
   │     ├─ UPDATE live_streams: source_node_id=node4, livekit_url=node4_url
   │     └─ PUBLISH teqlif:recording:stream_started {source_node_id:"node4"}
   │
   ▼  200: {livekit_url, token, room_name}
Host: connect(node4_url, token)  ← room_name={base}_p2, node4'te taze oda
_reconnectAttempts = 0, yayın devam eder

(~2dk sonra) node3 boot eder:
   _recover_orphaned() → Part 1 MKV → encoding → MinIO
node4 recorder (pub/sub'dan başladı):
   Normal kayıt → Part 2 MKV → MinIO
```

#### Backend — `is_node_healthy()` + `allocate_node(exclude_node_id)`

```python
# edge_orchestrator.py — iki ekleme:

async def is_node_healthy(self, node_id: str) -> bool:
    all_m = await self.get_all_metrics()
    node = next((m for m in all_m if m.get("node_id") == node_id), None)
    return (
        node is not None
        and node.get("services", {}).get("livekit", {}).get("healthy", False)
    )

# allocate_node() imzasına opsiyonel parametre:
async def allocate_node(
    self, service_type: ServiceType, exclude_node_id: str | None = None
) -> Dict[str, Any]: ...

# _pick_media() içinde tek satır ekleme:
candidates = [
    m for m in metrics
    if "media" in m.get("node_type", [])
    and m.get("services", {}).get("livekit", {}).get("healthy", False)
    and m.get("livekit_url")
    and m.get("node_id") != exclude_node_id   # ← yeni
]
```

#### Backend — `FailoverStreamCommand`

```python
# backend/app/use_cases/streams/commands/failover_stream.py
class FailoverStreamCommand:
    def __init__(self, uow: AbstractUnitOfWork, redis): ...

    async def execute(self, stream_id: int, caller_id: int) -> StreamTokenOut:
        async with self.uow:
            stream = await self.uow.streams.get(id=stream_id)
            if not stream or stream.status != "live":
                raise NotFoundException(code="STREAM_NOT_FOUND")
            if stream.host_id != caller_id:
                raise ForbiddenException(code="NOT_STREAM_HOST")

            if await orchestrator.is_node_healthy(stream.source_node_id):
                raise BadRequestException(code="NODE_STILL_HEALTHY")

            rl_key = f"teqlif:stream:failover_rl:{stream_id}"
            if not await self.redis.set(rl_key, "1", ex=300, nx=True):
                raise BadRequestException(code="FAILOVER_RATE_LIMITED")

            new_node = await orchestrator.allocate_node(
                ServiceType.MEDIA, exclude_node_id=stream.source_node_id
            )
            if new_node["node_id"].startswith("fallback"):
                raise ServiceUnavailableException(code="NO_NODES_AVAILABLE")

            # LiveKit Redis DB:1 room-node pinning tuzağından kaçın:
            # Aynı room_name node4'te açılamaz — Redis hâlâ node3'e kilitli.
            # Yeni bağımsız oda adı türet: {base}_p{part_number}
            part_count = await self.uow.session.scalar(
                text("SELECT COUNT(*) FROM stream_recordings WHERE stream_id=:sid"),
                {"sid": stream_id},
            )
            part_number  = (part_count or 0) + 1
            base_room    = stream.room_name.split("_p")[0]   # önceki part suffix'i temizle
            new_room_name = f"{base_room}_p{part_number}"

            stream.source_node_id = new_node["node_id"]
            stream.livekit_url    = new_node["livekit_url"]
            stream.room_name      = new_room_name
            await self.uow.session.flush()

        await self.redis.publish("teqlif:recording:stream_started", json.dumps({
            "stream_id":      stream.id,
            "room_name":      new_room_name,
            "host_id":        stream.host_id,
            "source_node_id": new_node["node_id"],
        }))

        user = await self.uow.users.get(id=caller_id)
        token = make_livekit_token(new_room_name, user, can_publish=True)
        return StreamTokenOut(
            livekit_url=new_node["livekit_url"],
            token=token,
            room_name=new_room_name,
        )
```

#### Flutter — `_tryFailover()` (host_stream_view_model.dart)

```dart
// scheduleReconnect() içinde — onNavigateHome?.call() yerine:
if (_reconnectAttempts >= _kMaxReconnectAttempts) {
  _tryFailover();
  return;
}

Future<void> _tryFailover() async {
  try {
    final newToken = await _stream.failoverStream(_token!.streamId);
    _token = newToken;
    _reconnectAttempts = 0;
    _reconnectTimer = Timer(Duration.zero, _reconnect);
  } on AppException catch (e) {
    if (e.code == 'NODE_STILL_HEALTHY') {
      // Node anlık glitch — normal reconnect'e sıfırla
      _reconnectAttempts = 0;
      scheduleReconnect();
      return;
    }
    onNavigateHome?.call();
  } catch (_) {
    onNavigateHome?.call();
  }
}
```

`stream_service.dart`'a:

```dart
// stream_service.dart — package:http/http.dart kullanır (Dio değil):
Future<StreamTokenOut> failoverStream(int streamId) async {
  final headers = await _headers();
  final resp = await http.post(
    Uri.parse('${_api.config.baseUrl}/streams/$streamId/failover'),
    headers: headers,
  );
  if (resp.statusCode >= 400) _throwHttpError(resp.statusCode, resp.body);
  return StreamTokenOut.fromJson(jsonDecode(resp.body));
}
```

#### Room Name Kararı — LiveKit Redis DB:1 Room-Node Pinning

node3 ve node4 LiveKit instance'ları aynı Redis DB:1'i paylaşır (`livekit.yaml: redis.address: 127.0.0.1:6379, db: 1` — her node'da HAProxy aynı master'a yönlenir). LiveKit distributed modda bir oda oluşturulduğunda `room:{room_name} → node3` kaydını Redis'e yazar. Başka bir node aynı oda adıyla bağlantı istediğinde Redis'e bakar, node3'e proxy yapar.

node3 çöktüğünde bu Redis kaydı **TTL dolana kadar yerinde kalır**. TTL ~30–60s; failover hedefimiz ~5s. node4 `abc123` odasına bağlanmak istediğinde Redis "Bu oda node3'te" der → proxy kurulamaz → failover bloklanır.

`stream.room_name` **failover sırasında değiştirilir**; yeni oda adı `{base_room_name}_p{part_number}` formatında türetilir (relay odasında kullanılan `_relay_` prefix deseniyle aynı mantık). Bu bağımsız yeni bir oda olduğu için Redis'te çakışma yoktur. Flutter token ile birlikte dönen `room_name`'i kullandığı için istemci tarafında sıfır sürtünmeyle yeni odaya bağlanır.

#### Viewer Downtime — Hızlı Failover Yolu

`join_stream.py` host token talebinde `is_node_healthy(source_node_id)` kontrolü ekler. Node ölüyse `NODE_UNAVAILABLE` hata kodu döner. `HostStreamViewModel` bu kodu ilk denemede aldığında 7 denemenin bitmesini beklemeden doğrudan `_tryFailover()` çağırır:

```dart
// host_stream_view_model.dart — _reconnect() içinde:
} on AppException catch (e) {
  if (e.code == 'STREAM_ENDED') { onNavigateHome?.call(); return; }
  if (e.code == 'NODE_UNAVAILABLE') {
    _tryFailover();   // 7 deneme beklemeden anında failover
    return;
  }
  scheduleReconnect();
}
```

Failover süresi: node3 crash → ilk reconnect denemesi (~2s) → `NODE_UNAVAILABLE` → failover API (~1s) → node4 bağlantı (~2s): **~5s**.

#### İzleyici Yarış Durumu (Viewer Race Condition)

Host failover isteği yoldayken (3–5 saniyelik pencere) yeni bir izleyici `join_stream` çağırırsa veya mevcut izleyiciler koptuğu için yeniden bağlanmaya çalışırsa, `live_streams.source_node_id` henüz node4 olarak güncellenmemiştir — izleyici ölü node3'e yönlendirilir.

`join_stream.py` **izleyici token talebi** için de `is_node_healthy(source_node_id)` kontrolü yapar. Node ölüyse izleyiciye `STREAM_FAILOVER_IN_PROGRESS` (HTTP 503) döner — izleyici failover başlatamaz, yalnızca bekler:

```python
# join_stream.py — izleyici token talebi:
if not await orchestrator.is_node_healthy(stream.source_node_id):
    raise ServiceUnavailableException(code="STREAM_FAILOVER_IN_PROGRESS")
```

Flutter izleyici ekranı bu kodu aldığında bağlantı UI yerine "Yayın aktarılıyor, lütfen bekleyin…" gösterir ve 2s sonra otomatik tekrar dener:

```dart
// viewer_stream_view_model.dart — join stream hata yönetimi:
} on AppException catch (e) {
  if (e.code == 'STREAM_FAILOVER_IN_PROGRESS') {
    _setStatus(ViewerStatus.failoverWaiting);
    Future.delayed(const Duration(seconds: 2), _joinStream);
    return;
  }
}
```

Failover tamamlanınca (DB'de `source_node_id = node4`) izleyicinin retry isteği artık node4 URL'ini alır.

#### Relay ile Etkileşim

Relay node3'e bağlıydı → crash → relay subprocess ölür → `_reap_finished()` → DEL `live:relay:ready + needed`. Failover sonrası node4 source olur; izleyici kapasitesi gereksinirse relay yeniden başlatılabilir.

#### Recording Sürekliliği

| | Kayıt | Akış |
|-|-------|------|
| Part 1 | node3 crash öncesi MKV | Salvage → encoding → MinIO (`status='available'`) |
| Part 2 | node4 failover pub/sub tetikledi | Normal kayıt → MinIO (`status='available'`) |
| Birleştirme | Part 1 + Part 2 her ikisi `available` olduğunda | ARQ worker `stream_concat_task` — MinIO'dan indir → ffprobe → concat/re-encode → MinIO yükle → part'ları sil |

#### Concat Pipeline — Dağıtık Dosya Konumu

`encoder.py`'nin `_maybe_concat_parts()` tasarımında kritik bir fiziksel kısıt vardır: Part 1 node3 diskindedir (`/var/recordings/encoded/123_part1.mp4`), Part 2 ise node4 diskindedir. Hiçbir edge node her iki dosyaya da yerel disk erişimine sahip değildir — `ffmpeg -f concat` yerel dosya olmadan çalışmaz.

Concat işi node1 üzerindeki ARQ worker'a (`stream_concat_task`) devredilir. Her iki part MinIO'ya yüklenmiştir; node1 her ikisini MinIO'dan indirir, concat yapar, sonucu MinIO'ya yükler:

```python
# backend/app/tasks/stream_concat_task.py (ARQ worker, node1)
async def stream_concat_task(ctx, stream_id: int):
    """Her iki part available olduğunda tetiklenir."""
    recs = await db.fetch(
        "SELECT id, encoded_path, part_number FROM stream_recordings "
        "WHERE stream_id=$1 AND status='available' AND is_concat_result=false "
        "ORDER BY part_number",
        stream_id,
    )
    if len(recs) < 2:
        return  # henüz her iki part hazır değil

    # ARQ cron üst üste binme koruması: re-encode 6+ dakika sürebilir,
    # bir sonraki cron tetiklemesi (2dk) aynı stream'i tekrar yakalar.
    lock_key = f"teqlif:lock:concat:{stream_id}"
    if not await ctx["redis"].set(lock_key, "1", ex=1800, nx=True):
        return  # başka bir worker bu stream'i zaten işliyor

    work_dir = Path(f"/tmp/concat_{stream_id}")
    work_dir.mkdir(exist_ok=True)
    try:
        for rec in recs:
            local = work_dir / f"part{rec['part_number']}.mp4"
            await minio.fget_object("teqlif", rec["encoded_path"], str(local))
        await _concat_or_reencode(work_dir, recs, stream_id)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        await ctx["redis"].delete(lock_key)
```

#### part_number Ataması (recorder.py INSERT)

`stream_recordings` tablosundaki `part_number SMALLINT nullable` sütunu `recorder.py` INSERT sorgusunda doldurulmalıdır; aksi hâlde `partNone.mp4` üretilir ve `ORDER BY part_number` bozulur. `recorder.py` kayıt açarken mevcut kayıt sayısından bir sonrakini hesaplar:

```python
# recorder.py — yeni kayıt açarken part_number atanır:
part_number = await conn.fetchval(
    "SELECT COALESCE(MAX(part_number), 0) + 1 FROM stream_recordings WHERE stream_id=$1",
    stream_id,
)
# INSERT ... part_number=$N ...
```

İlk kayıt (Part 1, normal yayın): `MAX` NULL → `COALESCE(NULL, 0)` = 0 → part_number = **1**.  
İkinci kayıt (Part 2, failover sonrası): `MAX` = 1 → part_number = **2**.

---

Part'ların `available` durumu → concat tetiklemesi: `encoder.py`'de Redis bağlantısı yoktur — pub/sub yayını yapamaz. `stream_concat_task`, `archive_recordings_task` ve `notify_new_recordings_task` ile aynı ARQ **cron** task deseniyle çalışır: her N dakikada bir (`worker.py`'de `cron(stream_concat_task, minute={...})`) DB'yi tarar ve birden fazla `available` part'a sahip stream'leri bulur:

```python
# stream_concat_task.py — cron trigger mantığı + ARQ distributed lock:
async def stream_concat_task(ctx: dict) -> None:
    rows = await db.fetch(
        "SELECT stream_id, COUNT(*) as part_count FROM stream_recordings "
        "WHERE status='available' AND is_concat_result=false "
        "GROUP BY stream_id HAVING COUNT(*) >= 2"
    )
    for row in rows:
        await _do_concat(ctx, row["stream_id"])
```

#### FFmpeg Resolution Mismatch Koruması

Failover sırasında yayıncının telefonu çözünürlük, frame rate veya yön değiştirebilir (720p → 480p, portrait → landscape). `ffmpeg -f concat -c copy` bu durumda video stream'ini bozar — Part 2'ye geçişte görüntü donar veya yeşil ekrana döner.

`_concat_or_reencode()` concat öncesi her iki parçayı `ffprobe` ile denetler:

```python
async def _probe(path: Path) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(path),
        stdout=asyncio.subprocess.PIPE,
    )
    out, _ = await proc.communicate()
    streams = json.loads(out)["streams"]
    v = next(s for s in streams if s["codec_type"] == "video")
    return {
        "width": v["width"], "height": v["height"],
        "r_frame_rate": v["r_frame_rate"], "codec_name": v["codec_name"],
        "sample_rate": next(
            (s["sample_rate"] for s in streams if s["codec_type"] == "audio"), None
        ),
    }

async def _concat_or_reencode(work_dir: Path, recs, stream_id: int):
    p1 = work_dir / "part1.mp4"
    p2 = work_dir / "part2.mp4"
    out = work_dir / "output.mp4"
    probe1, probe2 = await asyncio.gather(_probe(p1), _probe(p2))

    parts_file = work_dir / "parts.txt"
    parts_file.write_text(f"file '{p1}'\nfile '{p2}'\n")

    compatible = (
        probe1["width"]        == probe2["width"]        and
        probe1["height"]       == probe2["height"]       and
        probe1["r_frame_rate"] == probe2["r_frame_rate"] and
        probe1["codec_name"]   == probe2["codec_name"]   and
        probe1["sample_rate"]  == probe2["sample_rate"]
    )

    if compatible:
        cmd = ["ffmpeg", "-f", "concat", "-safe", "0", "-i", str(parts_file),
               "-c", "copy", str(out)]
    else:
        # Re-encode: çözünürlük/codec mismatch'i gider
        cmd = ["ionice", "-c", "3", "nice", "-n", "10",
               "ffmpeg", "-f", "concat", "-safe", "0", "-i", str(parts_file),
               "-vf", "scale=1280:720", "-r", "30",
               "-c:v", "libx264", "-preset", "fast", "-crf", "23",
               "-c:a", "aac", "-ar", "44100", str(out)]
        logger.warning("Concat re-encode: stream_id=%d p1=%s p2=%s",
                       stream_id, probe1, probe2)

    proc = await asyncio.create_subprocess_exec(*cmd)
    await proc.wait()
    # MinIO yükleme ve temizlik aşağıda
```

Re-encode yolu `ionice -c 3 nice -n 10` ile düşük öncelikte çalışır — node1'deki normal ARQ görevlerini etkilemez.

#### MinIO Storage Hijyeni (Concat Sonrası Part Temizliği)

Concat tamamlandıktan sonra MinIO'da 3 dosya bulunur:
- `streams/123/part1.mp4` (~500 MB)
- `streams/123/part2.mp4` (~500 MB)
- `streams/123/123.mp4` (~1 GB, `is_concat_result=true`)

Part dosyaları gereksizdir. `stream_concat_task` MinIO'ya başarılı yükleme yaptıktan hemen sonra temizler:

```python
# stream_concat_task.py — concat başarılı, temizlik:
for rec in recs:
    await minio.remove_object("teqlif", rec["encoded_path"])
    await db.execute(
        "UPDATE stream_recordings "
        "SET status='merged_and_purged', archived_at=NOW(), updated_at=NOW() WHERE id=$1",
        rec["id"],
    )
logger.info("Part'lar temizlendi: stream_id=%d", stream_id)
```

`stream_recordings` tablosuna `merged_and_purged` durumu eklenir. Bu durumdaki satırlar izleme panolarında gizlenir — yalnızca `is_concat_result=true` satırı UI'a gösterilir.

---

## 6. CPU Koruma (ADR §29)

ADR §29 (`_resolve_max_parallel`) encode paralelliğini zaten dinamik belirliyor:

| Durum | N |
|-------|---|
| Aktif kayıt var (`len(recording_procs) > 0`) | 1 |
| Disk acil (`< disk_emergency_gb`) | 4 |
| Bakım penceresi | 4 |
| Normal atıl | 2 |

Relay de software transcoding yaptığı için bu tabloya bir satır eklenir:

| Durum | N |
|-------|---|
| Aktif kayıt **veya** aktif relay var | 1 |
| Disk acil | 4 |
| Bakım penceresi | 4 |
| Normal atıl | 2 |

`_resolve_max_parallel` içindeki ilk koşul şu hale gelir:

```python
if len(self._recording_procs) > 0 or len(self._relay_procs) > 0:
    return 1
```

`relay_procs` referansı `agent.py`'de `EncoderManager` oluşturulurken `relay_mgr._procs` olarak dependency injection ile aktarılır — ADR §29'daki `recording_procs=rec_mgr._procs` ile aynı pattern.

### Relay Sağlık İzleme

`relay.py`, `recorder.py:332-344` desenine sadık kalarak her relay sürecinin başlangıç ve bitişinde SQLite CRDT'ye yazar:

```python
await self._db.mark_ok(f"relay.{self._cfg.node_id}", expected_every_m=10080)
# veya hata durumunda:
await self._db.mark_fail(f"relay.{self._cfg.node_id}", expected_every_m=10080)
```

Böylece relay süreçleri gossip ve izleme panolarında görünür olur.

---

## 7. Uygulama Planı

### Yeni Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `teqlif-agent/livekit_relay.py` | Subprocess: source_node'a hidden participant olarak bağlanır, aldığı track'leri relay_node'da `relay_room` odasında yayınlar. `livekit_subscriber.py` baz alınır; MKVWriter yerine `rtc.LocalVideoTrack` + `rtc.LocalAudioTrack`. **H3**: `on_track_subscribed`'da `set_video_quality(HIGH)` zorunlu. İlk keyframe basıldıktan sonra `live:relay:ready:{room}` anahtarını TTL=30s ile yazar ve heartbeat döngüsüyle tazeler. `nice -n -5` ile başlatılır. Parametreler: `--source-url`, `--target-url`, `--room`, `--relay-room`, `--api-key`, `--api-secret` |
| `teqlif-agent/modules/relay.py` | Agent modülü: 15s sustained window kontrolü, relay_node sağlık ön kontrolü, `livekit_relay.py` subprocess'ini başlatır/durdurur/izler; `_reap_finished` anında cleanup; circuit breaker (10dk/2 yeniden başlatma); `_recover_orphaned()` başlangıç temizliği; `mark_ok`/`mark_fail` sağlık raporlama; kill switch kontrolü. **H6**: WARMING_UP→ACTIVE warmup süresi ölçülür; `teqlif_stream_relay_warmup_seconds` metriği; > 5s Telegram uyarısı |
| `backend/app/use_cases/streams/commands/failover_stream.py` | **Kural 3**: `FailoverStreamCommand` — guard kontrolleri (stream live, caller==host, node unhealthy, rate limit), `allocate_node(exclude_node_id)`, **room_name = `{base}_p{part_number}`** (Redis DB:1 room-node pinning tuzağından kaçınmak için), DB güncelleme (`source_node_id`, `livekit_url`, `room_name`), `teqlif:recording:stream_started` pub/sub ile Part 2 kaydı tetikleme, yeni host token dönme |
| `backend/app/tasks/stream_concat_task.py` | ARQ **cron** task (node1, `worker.py`'e eklenir): periyodik DB taraması — 2+ `available` part'ı olan stream'ler bulunur; MinIO'dan her iki parça indirilir; `ffprobe` çözünürlük/codec kontrolü; uyumluysa `-c copy`, değilse re-encode; birleşik MP4 MinIO'ya yüklenir (`is_concat_result=true`); part dosyaları MinIO'dan silinir; DB'de part satırları `merged_and_purged` yapılır |

### Değişecek Dosyalar

| Dosya | Değişiklik |
|-------|------------|
| `deploy/scale/V2.1/cluster.yaml` | `relay:` bloğu eklenir (`tx_threshold_mbps`, `min_viewers_teardown`, `heartbeat_interval_sec`, `ready_ttl_sec`). **H2**: `recording.recording_grace_seconds: 120` eklenir — `webhooks.py:_HOST_GRACE_SECONDS` ile eşleşmeli |
| `teqlif-agent` ana döngüsü | `relay.py` modülü entegre edilir; `net_tx_mbps` Redis'ten okunur (yeni okuyucu yazılmaz — zaten `edge:metrics:{node_id}`'de mevcut) |
| `backend/app/services/edge_orchestrator.py` | `StreamEndpoint` dataclass + `resolve_stream_endpoint(stream)` metodu eklenir; `live:relay:ready:{room}` kontrolü ve yük dengesi bu metotta yapılır. **H1**: `_fallback()` URL→node_id eşleştirmesi ile gerçek node_id döner. **Kural 3**: `is_node_healthy(node_id)` metodu + `allocate_node(exclude_node_id)` parametresi |
| `backend/app/use_cases/streams/commands/join_stream.py` | `orchestrator.resolve_stream_endpoint(stream)` çağrısı — Redis/routing kodu Command içine yazılmaz (CQRS/SRP). Host token talebinde `is_node_healthy(source_node_id)` kontrolü: ölü node → `NODE_UNAVAILABLE` hata kodu döner. **İzleyici Yarış Durumu**: izleyici token talebi için de aynı `is_node_healthy` kontrolü — ölü node → `STREAM_FAILOVER_IN_PROGRESS` (HTTP 503) döner |
| `backend/app/use_cases/streams/commands/lifecycle_commands.py` | Recording event payload'una `source_node_id` eklenir |
| `backend/app/use_cases/streams/commands/start_stream.py` | Orchestrator'dan dönen `node["node_id"]` stream'e `source_node_id` olarak yazılır |
| `backend/app/models/stream.py` | `source_node_id: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)` eklenir |
| `backend/alembic/versions/zzzzzu_add_source_node_id_to_live_streams.py` | `source_node_id VARCHAR(50) nullable` migration; `stream_recordings` tablosuna `is_concat_result BOOLEAN DEFAULT false` ve `part_number SMALLINT nullable` sütunları eklenir; `status` CHECK kısıtına `merged_and_purged` değeri eklenir |
| `backend/app/routers/streams.py` | **Kural 3**: `POST /api/streams/{id}/failover` endpoint — `FailoverStreamCommand` çağırır |
| `deploy/scale/V2.1/teqlif-agent/modules/recorder.py` | `source_node_id != self._cfg.node_id` ise kayıt pas geçilir; fallback poll `OR source_node_id IS NULL`. **H1** savunma: `source_node_id in (None, "fallback")` → URL eşleştirme. **Kural 1**: `_recover_orphaned()` MKV varsa `encoding`'e alır (Salvage). **Kural 2**: `_purge_ghost_streams()` LiveKit ListRooms kontrolü — init sırası: recover → purge → sync. **part_number**: INSERT sorgusunda `COALESCE(MAX(part_number),0)+1` ile atanır |
| `deploy/scale/V2.1/teqlif-agent/modules/encoder.py` | `relay_procs` farkındalığı — relay aktifken `_MAX_PARALLEL = 1`. **H4**: FFmpeg subprocess `ionice -c 3` ile başlatılır. Concat tetikleme encoder.py'den yapılmaz — `encoder.py`'de Redis yoktur; `stream_concat_task` ARQ cron görevi DB'yi periyodik tarayarak concat adaylarını tespit eder |
| `deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py` | **H2**: `on_participant_disconnected` → host ayrılınca `recording_grace_seconds` timer başlatılır; `on_participant_connected` host dönünce timer iptal eder; timer dolarsa `stop_evt.set()`; relay/izleyici ayrılması kaydı etkilemez |
| `backend/app/routers/webhooks.py` | **H5**: `room_finished` handler'a `if "_relay_" in room_name: return` filtresi |
| `mobile/lib/screens/live/viewmodels/host_stream_view_model.dart` | **Kural 3**: `_tryFailover()` metodu — `_kMaxReconnectAttempts` aşılınca `onNavigateHome` yerine çağrılır; `NODE_STILL_HEALTHY` durumunda retry sıfırlanır. `NODE_UNAVAILABLE` kodu gelince `_kMaxReconnectAttempts` beklemeden doğrudan `_tryFailover()` çağrılır (~5s failover yolu) |
| `mobile/lib/services/stream_service.dart` | **Kural 3**: `failoverStream(int streamId)` metodu — `POST /api/streams/{id}/failover` |
| `mobile/lib/screens/live/viewmodels/viewer_stream_view_model.dart` | **İzleyici Yarış Durumu**: `_joinStream()` içinde `STREAM_FAILOVER_IN_PROGRESS` (503) alınca `ViewerStatus.failoverWaiting` durumuna geçilir, 2s sonra otomatik tekrar dener; kullanıcı "Yayın aktarılıyor, lütfen bekleyin…" mesajını görür |
| `backend/app/config.py` | **H1**: `edge_livekit_node_map: dict[str, str] = {}` alanı eklenir (key=livekit_url, value=node_id); ortam değişkeni `EDGE_LIVEKIT_NODE_MAP` ile doldurulur |
| `backend/app/worker.py` | `stream_concat_task` ARQ cron görevi `worker.py` cron listesine eklenir (`stream_recording_tasks` import'u genişletilir) |
| `deploy/scale/V2.1/teqlif-agent/modules/cleaner.py` | `merged_and_purged` DB temizliği eklenir: `archived_at < NOW() - INTERVAL '15 days' AND (status = 'archived' OR status = 'merged_and_purged')` — concat sonrası part satırları birikip çöp oluşturmaz |

### livekit_relay.py Çalışma Prensibi

```
source_room (source_node) → VideoStream/AudioStream → raw frames (decode)
                                                             ↓
relay_room  (relay_node)  ← LocalVideoTrack/LocalAudioTrack ← libvpx encode
```

Simetrik: yayın hangi node'da başlarsa başlasın, `--source-url` ve `--target-url` parametreleriyle herhangi bir node relay olabilir.
