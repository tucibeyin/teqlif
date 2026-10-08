# Stream Kayıt Sistemi — V1.3 Bulgular

**Tarih:** 2026-10-08  
**Kapsam:** Kayıt yaşam döngüsü, mimari kararlar, API durumu, mobil UI/UX, implementasyon planı

---

## 0. Uygulama İlkeleri

Bu feature, aşağıdaki prensiplerle implement edilir:

| Prensip | Kaynak | Bu Feature'a Etkisi |
|---------|--------|---------------------|
| **Clean Architecture** | `teqlif_architectural_decisions.md` | Yeni endpointler use-case sınıfları üzerinden; Router → UseCase → Model zinciri korunur |
| **MVVM** | ADR §8 | Her ekranın bir `AsyncNotifier` ViewModel'i var; Screen sadece render eder |
| **OTA Localization** | ADR §1 | Tüm UI stringleri ARB'a eklenir, `loc.t()` / `loc.tOr()` ile tüketilir |
| **Merkezi Error Handling** | ADR §3 | Her `catch` bloğu `handleError(e, ref.read(localizationProvider))` çağırır |
| **Async Buton Pattern** | ADR §5 | Async tetikleyen butonlar `TeqAsyncButton`; provider state gerekirse `TeqButton(isLoading:...)` |
| **Cache Taksonomisi** | ADR §9 | Kayıt listesi = LIFECYCLE; Presigned URL = EPHEMERAL |
| **Deployment Workflow** | ADR §13 | Local → push → pull (node) → `sudo teqlif-restart` |

**Referans ekran:** `create_listing_screen.dart` — tüm pattern'lar orada uygulandı.

---

## 1. Mimari Genel Bakış

Stream kayıt sistemi üç fiziksel katmana yayılmış:

| Katman | Node | Sorumluluk |
|--------|------|------------|
| Kayıt + Encode | node3 / node4 | FFmpeg WHEP kayıt, H.264 encode, MinIO transfer |
| Servis + API | node1 | Presigned URL üretimi, ARQ durum geçişleri |
| Backup | node2 | Günlük MinIO mirror — hedef 05:30 UTC (bkz. §9) |

Her LiveKit node (3/4) kendi stream'lerini bağımsız kaydeder. `RecordingManager` lider seçimine bağlı değil.

---

## 2. Durum Makinesi

```
recording → encoding → encoded ⇄ transferring → available → expired → archived
                  ↘         ↗          ↘ (dosya yok)
                failed              failed
```

- `encoding → failed`: FFmpeg encode hatası
- `transferring → encoded`: `mc cp` hatası → bir sonraki pencerede retry
- `transferring → failed`: sadece encoded dosya fiziksel olarak kaybolmuşsa (nadir)
- `archived` son aktif durum — `deleted` geçişi henüz implement edilmemiş (bkz. §9)

### Durum Tanımları

| Durum | Aktör | Tetikleyici | Açıklama |
|-------|-------|-------------|----------|
| `recording` | teqlif-agent (recorder.py) | Stream `live` — her yayın, zorunlu | FFmpeg WHEP açık, MKV `/var/recordings/raw/` yazılıyor |
| `encoding` | teqlif-agent (recorder.py) | FFmpeg kapanır | Ham MKV → H.264/AAC 720p, `crf=23 veryfast` |
| `encoded` | teqlif-agent (encoder.py) | Encode tamamlanır | Ham dosya silinir, transfer penceresi bekleniyor |
| `transferring` | teqlif-agent (encoder.py) | Transfer penceresi açılır | `mc cp` → node1 MinIO; hata → `encoded`'a geri döner |
| `available` | teqlif-agent (encoder.py) | `mc cp` başarılı | `available_at=NOW()`, `expires_at=NOW()+24h`, lokal encode silinir |
| `expired` | ARQ node1 — her 30 dk (:00 ve :30) | `expires_at < NOW()` | API 410 döner, MinIO dosyası hâlâ var |
| `archived` | ARQ node1 — her saat :15 | `transferred_at + 4 gün` | MinIO lifecycle dosyayı silmiş, node2 backup almış |
| `failed` | teqlif-agent | Encode hatası veya encode dosyası kaybolması | `error_message` dolu |

### DB'den Silinme

`janitor.py` `stream_recordings_15d` policy'si `archived_at + 15 gün` geçen satırları sayar ve loglar — silmez. `cleanup_actions.sh` mevcut değil; `deleted_at` kolonu ve `deleted` durumu DB şemasında tanımlı ama geçiş kodu implement edilmemiş. Şu an satırlar `archived` olarak kalır.

---

## 3. Zaman Çizelgesi

```
T+0h    Stream biter → recording → encoding başlar
T+?h    Encode tamamlanır → encoded
        (yayın uzunluğuna bağlı; kısa yayınlarda dakikalar)

T+3h    Transfer penceresi açılır (UTC 03:00, disk ≥ 15 GB)
        → transferring → available

T+5h    Transfer penceresi kapanır (UTC 05:00 — hedef, bkz. §9)

T+5:30h minio_backup çalışır (UTC 05:30 — hedef)
        Tüm transferler backup'a girer → RPO < 1 saat

T+27h   expires_at geçer → expired
        (ARQ expire_recordings_task, her 30 dk)

T+4g    MinIO lifecycle dosyayı siler → archived
        (ARQ archive_recordings_task, her saat :15)

T+19g   janitor.py sayar/loglar — satır silme implement edilmemiş
```

### Transfer Penceresi Kuralları (UTC / TR)

| Disk Durumu | Mevcut Pencere | Hedef Pencere | TR karşılığı |
|-------------|---------------|---------------|--------------|
| ≥ 15 GB boş | 03:00 – 08:00 | **03:00 – 05:00** | 06:00 – 08:00 TR |
| 10–15 GB boş | 02:00 – 08:00 | **02:00 – 05:00** | 05:00 – 08:00 TR |
| < 10 GB boş | Her an (acil) | Her an (acil) — `--limit-upload 30M` şart, bkz. §9 |

> **RPO Notu:** Mevcut pencere 08:00 UTC = 11:00 TR'de bitiyor; minio_backup 04:00 UTC'de çalışıyor. 04:00–08:00 arası inen dosyalar ertesi güne kalıyor. Pencere sonu 05:00 + backup 05:30 ile tüm transferler backup'a girmiş olur; sistem 06:00 UTC = 09:00 TR kullanıcı girişinden önce boşta.

---

## 4. Dosya Yolları

```
Kayıt (ham)  : /var/recordings/raw/{stream_id}_{timestamp}.mkv         (node3/4)
Encode       : /var/recordings/encoded/{stream_id}_{timestamp}.mp4      (node3/4)
minio_key    : recordings/{stream_id}/{filename}.mp4                    (bucket-relative)
MinIO (prod) : bucket=teqlif  key=recordings/{stream_id}/{filename}.mp4 (node1)
Backup       : /project/teqlif/backups/minio/teqlif/recordings/…        (node2)
```

`minio_key` DB'de bucket adı olmadan saklanır. Bucket (`teqlif`) config'den (`minio_bucket`) ayrı gelir.

---

## 5. Mimari Kararlar

### 5.1 Zorunlu Kayıt

Canlı yayın kaydı host tercihine bırakılmıyor. Her yayın sistem tarafından otomatik kaydedilir:

- Müzayede anlaşmazlıkları, fiyat itirazları
- İçerik moderasyonu ve kullanıcı şikayetleri  
- Platform koruması, dolandırıcılık tespiti

### 5.2 recording_enabled Tasarım Hatası

Mevcut `recording_enabled` boolean'ı iki bağımsız kararı tek alana sıkıştırmış:

```
recording_enabled = True  →  HEM kayıt yap  HEM izlemeye izin ver   ← YANLIŞ
recording_enabled = False →  NE kayıt yap   NE izlemeye izin ver    ← YANLIŞ
```

Doğru ayrım:

| Karar | Kim verir | Kural |
|-------|-----------|-------|
| Kayıt yap | **Sistem** | Her yayın, her zaman |
| İzleme izni | **PRO statüsü** | Sadece PRO host, 24h penceresi |

`recording_enabled` beş yerde kaldırılacak / değiştirilecek (bkz. §9):

| Yer | Mevcut | Hedef |
|-----|--------|-------|
| `live_streams` DB kolonu | `default=False` | Kaldırılacak |
| `StartStreamRequest` şeması | İsteğe bağlı alan | Kaldırılacak |
| `start_stream` use case | DB'ye yazıyor | Kaldırılacak |
| `RecordingManager._sync_recordings()` | `AND ls.recording_enabled = TRUE` | Filtre kaldırılacak |
| `GET /streams/{id}/recording` | `recording_enabled` kontrolü | PRO kontrolü ile değiştirilecek |

`recording_enabled` mobil kodda kullanılmıyor (grep: sıfır sonuç).

### 5.3 Erişim Kuralları

| Kural | Açıklama |
|-------|----------|
| Sadece host | `host_id == current_user.id`; izleyiciler erişemez |
| Sadece PRO | Host PRO üye olmalı — mevcut endpoint'e PRO kontrolü henüz eklenmedi |
| 24 saat | `available_at` → `expires_at` arası |
| Sadece `available` | `expired` / `archived` durumunda presigned URL verilmez |

İzleyici erişimi kapsam dışı bırakıldı. Gerekçe: müzayede içeriklerinde host gizliliği, hukuki risk, içerik kontrolü.

### 5.4 Depolama Etkisi

Tüm yayınların kaydedilmesi depolama baskısı yaratmaz:
- node3/4 lokal disk: encode biter bitmez MinIO'ya taşınıp silinir
- MinIO: 4 günlük lifecycle — otomatik silinme
- node2: 15 günlük DB retention

Ek önlem: `duration_secs < 60` olan yayınlar encode adımında atlanabilir.

---

## 6. API — Clean Architecture Uygulaması

### 6.1 Mevcut Endpoint

```
GET /streams/{stream_id}/recording
```

- `host_id == current_user.id` kontrolü var
- `recording_enabled = False` → 404 RECORDING_NOT_ENABLED *(kaldırılacak)*
- `status IN ('recording','encoding','encoded','transferring')` → 404 RECORDING_NOT_FOUND
- `status = 'available'` → presigned URL (1 saat geçerli)
- `status = 'expired' / 'archived'` → 410 RECORDING_EXPIRED
- Yanıt: `{ recording_id, url, available_at, expires_at }` — `duration_secs` dönmüyor

### 6.2 Mevcut Yardımcı Endpointler (Detay Ekranı için)

| Endpoint | Döndürdükleri |
|----------|---------------|
| `GET /analytics/seller-report/{stream_id}` | stream meta, auction özeti, ClickHouse metrikleri |
| `GET /streams/{stream_id}/commerce-activity` | Teklifler + DS siparişleri, zaman sıralı |

### 6.3 Yeni Endpointler — Use-Case Yapısı

Clean Architecture kuralı: Router → UseCase (Query/Command) → Model. Router hiçbir domain nesnesine doğrudan bağımlı değildir.

**`GET /recordings/my`**

```
Router: recordings.py
  └── GetMyRecordingsQuery(user_id, db).execute()
        └── SELECT stream_recordings JOIN live_streams
            WHERE host_id = user_id
              AND status IN ('recording','encoding','encoded','available','expired')
              AND recording_started_at > NOW() - INTERVAL '30 days'
            ORDER BY recording_started_at DESC
```

Yanıt alanları: `stream_id, stream_title, status, duration_secs, encoded_size_bytes, available_at, expires_at, recording_started_at`

Hata formatı (ADR §6):
```json
{ "success": false, "error": { "code": "RECORDING_NOT_FOUND", "message": "..." } }
```

**`GET /streams/{stream_id}/recording-summary`**

```
Router: streams.py
  └── GetRecordingSummaryQuery(stream_id, user_id, db, ch).execute()
        ├── stream meta (live_streams)
        ├── metrics (ClickHouse — seller-report ile aynı sorgu)
        ├── auctions[] + bids[] (Auction JOIN Bid — auction_id migration sonrası)
        ├── direct_sales[] + orders[] (DirectSale JOIN DirectSaleOrder)
        └── gifts{} (GiftEvent — ilk kez endpointte)
```

Her kullanıcı satırında `user_id + avatar_url` dönmeli (profil navigasyonu için). `avatar_url`: `kUploadsHost + user.avatar_path` (ADR `feedback_uploads_url.md` uyumu).

### 6.4 Hata Kodları

Yeni `AppException` subclass'ları `ErrorMapper`'a eklenecek:

| Kod | Durum | Flutter'da |
|-----|-------|-----------|
| `RECORDING_NOT_FOUND` | 404 | `loc.t('errorRecordingNotFound')` |
| `RECORDING_EXPIRED` | 410 | `loc.t('errorRecordingExpired')` |
| `RECORDING_NOT_AVAILABLE` | 404 | `loc.t('errorRecordingNotAvailable')` |

---

## 7. Ticaret Verisi — DB vs API Analizi

### 7.1 DB'de Var, API'de Yok

| Model | Eksik Alan | Etkisi |
|-------|-----------|--------|
| `Auction` | `proof_image_url` | Modalda ürün fotoğrafı yok |
| `Auction` | `buy_it_now_price` | Hemen al fiyatı gösterilemiyor |
| `Auction` | `winner_id` | Kazanan profil navigasyonu yok |
| `Bid` | `bidder_id` | Teklif veren profil navigasyonu yok |
| `Bid` | `auction_id` — **tabloda yok** | Teklifler müzayede bazında gruplanamıyor |
| `DirectSale` | `product_image_url` | Modalda ürün fotoğrafı yok |
| `DirectSale` | `total_stock`, `remaining_stock`, `viewer_count_at_start` | Stok ve izleyici bilgisi yok |
| `DirectSaleOrder` | `buyer_id` | Alıcı profil navigasyonu yok |
| `GiftEvent` | Tümü | **Hiçbir endpointte yok** |

> **Kritik:** `Bid` tablosunda `auction_id` kolonu yok — teklifler yalnızca `stream_id`'ye bağlı. Müzayede bazında gruplamak için ya Alembic migration gerekir ya da zaman aralığı heuristiği kullanılır.

### 7.2 Profil Navigasyonu Gerekliliği

Modal'da "@ kullanıcı → Profil" için `user_id` zorunlu. Mevcut endpointlerin hiçbirinde `actor_id` / `buyer_id` / `winner_id` / `sender_id` dönmüyor.

### 7.3 Yeni Endpoint — recording-summary Yanıt Şeması

```json
{
  "stream": {
    "title", "started_at", "ended_at", "peak_viewer_count", "thumbnail_url"
  },
  "metrics": {
    "unique_viewers", "total_revenue", "hesitation_count", "recommendation"
  },
  "auctions": [{
    "auction_id", "item_name", "proof_image_url",
    "start_price", "final_price", "buy_it_now_price", "is_bought_it_now",
    "bid_count", "duration_minutes", "sold",
    "winner": { "user_id", "username", "avatar_url" },
    "bids":   [{ "user_id", "username", "avatar_url", "amount", "created_at" }]
  }],
  "direct_sales": [{
    "sale_id", "title", "product_image_url", "price",
    "total_stock", "sold_count", "viewer_count_at_start",
    "orders": [{ "user_id", "username", "avatar_url", "quantity", "unit_price", "created_at" }]
  }],
  "gifts": {
    "total_teqlik", "total_host_share", "sender_count",
    "events": [{ "user_id", "username", "avatar_url", "gift_name", "cost_teqlik", "sent_at" }]
  }
}
```

Bu endpoint `seller-report` ve `commerce-activity`'nin yerini almaz — liste ekranı için ikisi hâlâ kullanılır.

---

## 8. Mobil Ekranlar — MVVM + OTA

### 8.1 Genel MVVM Katman Yapısı

```
Model         RecordingItem, RecordingDetail, AuctionSummary, DirectSaleSummary, GiftSummary
              → DTO'lar, domain nesneleri; UI ve BuildContext bilmez

Repository    RecordingRepository
              → GET /recordings/my, GET /streams/{id}/recording, GET /streams/{id}/recording-summary
              → Hata: return Err(e); caller handleError ile yakalar
              → result.when(ok: ..., err: (e) => handleError(e, loc))

ViewModel     MyRecordingsNotifier  extends AsyncNotifier<List<RecordingItem>>
              RecordingDetailNotifier  extends AsyncNotifier<RecordingDetailState>
              → İş mantığı, cache yönetimi, durum geçişleri burada
              → BuildContext yok; TeqToast + handleError context-free çalışır

View          MyRecordingsScreen  extends ConsumerStatefulWidget
              RecordingDetailScreen  extends ConsumerStatefulWidget
              → ref.watch(myRecordingsProvider) ile state tüketir
              → setState yok; tüm aksiyonlar notifier metodlarına yönlendirilir
              → loc = ref.watch(localizationProvider); build() başında
```

### 8.2 PRO Hub Yerleşimi

"Yayın & Kitle" accordion'ı (`proHubTabAudience`, `0xFF14B8A6`) içinde 4. kart:

```dart
// pro_hub_screen.dart — build() başında:
final loc = ref.watch(localizationProvider);

// Kart tanımı:
_ToolCard(
  icon: Icons.video_library_outlined,
  iconColor: const Color(0xFFF97316),
  title: loc.t('proToolMyRecordingsTitle'),
  description: loc.t('proToolMyRecordingsDesc'),
  isPremium: isPremium,
  onTap: isPremium
      ? () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const MyRecordingsScreen()))
      : () => _showUpgrade(context),
)
```

Sıra: BestStreamTime → StreamAnalytics → Retargeting → **Canlı Yayınlarım**

### 8.3 Liste Ekranı (MyRecordingsScreen)

**ViewModel: `MyRecordingsNotifier`**

```dart
class MyRecordingsNotifier extends AsyncNotifier<List<RecordingItem>> {
  @override
  Future<List<RecordingItem>> build() => _fetch();

  Future<List<RecordingItem>> _fetch() async {
    final cached = RecordingsCacheService.getList();
    if (cached != null) return cached;
    final result = await ref.read(recordingRepositoryProvider).getMyRecordings();
    return result.when(
      ok: (data) {
        RecordingsCacheService.saveList(data);
        return data;
      },
      err: (e) {
        handleError(e, ref.read(localizationProvider));
        throw e;
      },
    );
  }

  Future<void> refresh() => ref.invalidateSelf();
}

final myRecordingsProvider =
    AsyncNotifierProvider<MyRecordingsNotifier, List<RecordingItem>>(
        MyRecordingsNotifier.new);
```

**View: `MyRecordingsScreen`**

```dart
class MyRecordingsScreen extends ConsumerStatefulWidget { ... }
class _MyRecordingsScreenState extends ConsumerState<MyRecordingsScreen> {

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final recordingsAsync = ref.watch(myRecordingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('proToolMyRecordingsTitle'))),
      body: recordingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(myRecordingsProvider)),
        data: (recordings) => recordings.isEmpty
            ? _EmptyView(loc: loc)
            : RefreshIndicator(
                onRefresh: () => ref.read(myRecordingsProvider.notifier).refresh(),
                child: ListView.builder(
                  itemCount: recordings.length,
                  itemBuilder: (_, i) => RecordingCard(item: recordings[i]),
                ),
              ),
      ),
    );
  }
}
```

**Ekran görünümü:**

```
┌─────────────────────────────────┐
│  ← Canlı Yayınlarım             │
├─────────────────────────────────┤
│  ┌───────────────────────────┐  │
│  │  "12 Ekim — Sabah"        │  │
│  │  48:32  •  720p           │  │
│  │  [● Hazırlanıyor...]      │  │  recording / encoding / encoded
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  "11 Ekim — Öğlen"        │  │
│  │  1s 12dk  •  720p         │  │
│  │  [▶ İzle]  Son: 3s 14dk  │  │  available + countdown → detay ekranı
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  "10 Ekim — Akşam"        │  │
│  │  22:10  •  720p           │  │
│  │  Süresi Doldu             │  │  expired / archived, opacity 0.5
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**Status chip — OTA string'ler:**

| `status` | Chip | OTA Key | Renk | Davranış |
|----------|------|---------|------|---------|
| `recording / encoding / encoded` | `● Hazırlanıyor` | `recordingStatusPreparing` | amber, pulse | dokunulamaz |
| `available` | `▶ İzle` | `recordingStatusWatch` | teal button | detay ekranına git |
| `available`, son 2 saat | `▶ İzle · 1s 45dk` | `recordingStatusExpiresIn` | orange, countdown | detay ekranına git |
| `expired / archived` | `Süresi Doldu` | `recordingStatusExpired` | tertiary, opacity 0.5 | dokunulamaz |

Countdown: `expires_at - DateTime.now()`, `Timer.periodic(1min)`. Oynatma sırasında expire olursa card anında `expired` state'e geçer.

**Hardcode string yasak:** `'Hazırlanıyor'`, `'İzle'`, `'Süresi Doldu'` doğrudan yazılmaz — `loc.t(key)` kullanılır.

### 8.4 Detay Ekranı (RecordingDetailScreen)

`available` karta tıklandığında açılır.

**ViewModel: `RecordingDetailNotifier`**

```dart
class RecordingDetailState {
  final String? playUrl;         // presigned URL veya null (fetch gerekiyor)
  final RecordingDetail? detail; // recording-summary yanıtı
  final bool urlExpired;
}

class RecordingDetailNotifier extends AsyncNotifier<RecordingDetailState> {
  @override
  Future<RecordingDetailState> build(String streamId) async {
    final url = await _resolvePlayUrl(streamId);
    final detail = await _fetchSummary(streamId);
    return RecordingDetailState(playUrl: url, detail: detail, urlExpired: false);
  }

  Future<String?> _resolvePlayUrl(String streamId) async {
    // expires_at guard — API'ye gitmeden önce kontrol
    final cached = RecordingsCacheService.getUrl(streamId);
    if (cached != null) {
      if (DateTime.now().isAfter(cached.expiresAt)) {
        RecordingsCacheService.clearUrl(streamId);
        return _fetchFreshUrl(streamId);
      }
      return cached.url;
    }
    return _fetchFreshUrl(streamId);
  }

  Future<String?> _fetchFreshUrl(String streamId) async {
    final result = await ref.read(recordingRepositoryProvider).getRecordingUrl(streamId);
    return result.when(
      ok: (r) {
        RecordingsCacheService.saveUrl(streamId, r.url, r.expiresAt);
        return r.url;
      },
      err: (e) {
        handleError(e, ref.read(localizationProvider));
        return null;
      },
    );
  }

  // 403 recovery — oynatma sırasında URL expire olursa
  Future<void> recoverUrl(String streamId) async {
    RecordingsCacheService.clearUrl(streamId);
    final freshUrl = await _fetchFreshUrl(streamId);
    state = AsyncData(state.value!.copyWith(playUrl: freshUrl));
  }

  Future<RecordingDetail?> _fetchSummary(String streamId) async {
    final cached = RecordingsCacheService.getSummary(streamId);
    if (cached != null) return cached;
    final result = await ref.read(recordingRepositoryProvider).getRecordingSummary(streamId);
    return result.when(
      ok: (d) {
        RecordingsCacheService.saveSummary(streamId, d);
        return d;
      },
      err: (e) {
        handleError(e, ref.read(localizationProvider));
        return null;
      },
    );
  }
}
```

**View: `RecordingDetailScreen`**

```dart
class RecordingDetailScreen extends ConsumerStatefulWidget {
  final String streamId;
  const RecordingDetailScreen({required this.streamId, super.key});
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen> {
  late VideoPlayerController _controller;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final detailAsync = ref.watch(recordingDetailProvider(widget.streamId));

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(),
        data: (state) => _buildContent(state, loc),
      ),
    );
  }
}
```

**Ekran yapısı:**

```
┌──────────────────────────────────────────────┐
│  ← "12 Ekim — Sabah Müzayedesi"             │
├──────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────┐│
│  │         VIDEO PLAYER (16:9)              ││  chewie + video_player
│  │         presigned URL — ViewModel'den    ││
│  └──────────────────────────────────────────┘│
│                                              │
│  1s 48dk  •  12 Eki  •  Pik: 234 izleyici  │
│                                              │
│  ─── Yayın Özeti ──────────────────────────│
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ 4.250 TL │  │ 23 teklif│  │ 9 satış  │  │
│  └──────────┘  └──────────┘  └──────────┘  │
│                                              │
│  ─── Ticaret Etkinliği ────────────────────│
│  [🔨 Rolex Submariner     SATILDI  3.450 TL]│
│  [🔨 Patek Philippe       KAZANANSIZ       ]│
│  [🛍 iPhone 15 Pro        5/10    750 TL   ]│
│  [🛍 AirPods Pro          10/10   1.500 TL ]│
│  [🎁 Hediyeler            1.240 teqlik     ]│
└──────────────────────────────────────────────┘
```

**Ticaret kartları:**

```
── Müzayede Kartı ─────────────────────────────
🔨  "Rolex Submariner"            [SATILDI ✓]
Başlangıç: 1.200 TL  →  Final: 3.450 TL
23 teklif  •  12 dk  •  Hemen Al: 5.000 TL
🏆 @ertankolcu                              ›

── Direkt Satış Kartı ─────────────────────────
🛍  "iPhone 15 Pro"           [5 / 10 SATILDI]
150 TL × 5 adet = 750 TL toplam
Stok: 5 kaldı                               ›

── Hediyeler Özet Kartı ───────────────────────
🎁  Hediyeler
Toplam: 1.240 teqlik  •  8 gönderici        ›
```

### 8.5 Bottom Modal İçerikleri

Karta tıklandığında `showModalBottomSheet` açılır.

**Müzayede Modalı:**
- `proof_image_url` tam genişlik (varsa)
- Başlangıç / satış fiyatı ve artış yüzdesi
- Hemen al fiyatı (kullanıldı mı?)
- Süre (dakika)
- Kazanan: avatar + username → profil navigasyonu (`user_id` ile)
- Tüm teklifler: avatar + username + tutar + zaman → her satır profil navigasyonu

**Direkt Satış Modalı:**
- `product_image_url` tam genişlik (varsa)
- Fiyat, toplam stok / satılan adet
- Başlama ve bitiş zamanı
- `viewer_count_at_start`
- Alıcılar: avatar + username + adet + tutar + zaman → profil navigasyonu

**Hediyeler Modalı:**
- Toplam teqlik ve host payı (`host_share`)
- Gönderici listesi: avatar + username + hediye adı + tutar + zaman → profil navigasyonu

**Modal içinde refresh yok** — veriler `RecordingDetailNotifier`'dan gelir, ayrı istek atılmaz.

### 8.6 Caching Stratejisi (LIFECYCLE + EPHEMERAL)

Video dosyasını indirip saklamak uygunsuz (720p 1 saat ≈ 2–4 GB, çevrimdışı ihtiyaç yok). Presigned URL cache'lenir; `expires_at` API isteği öncesi guard görevi yapar.

**Cache taksonomisi:**

| Katman | Sınıf | Anahtar | TTL | Kategori |
|--------|-------|---------|-----|---------|
| Kayıt listesi | `RecordingsCacheService` | `recordings:my` | 3 dk | LIFECYCLE |
| Presigned URL | `RecordingsCacheService` | `recording_url:{stream_id}` | 55 dk | EPHEMERAL |
| Summary | `RecordingsCacheService` | `recording_summary:{stream_id}` | 10 dk | LIFECYCLE |

**`RecordingsCacheService`** mevcut `CacheService` üzerine ince bir wrapper:

```dart
class RecordingsCacheService {
  static List<RecordingItem>? getList() { ... }
  static void saveList(List<RecordingItem> data) { ... }  // TTL: 3 dk

  static CachedUrl? getUrl(String streamId) { ... }
  static void saveUrl(String streamId, String url, DateTime expiresAt) { ... }  // TTL: 55 dk
  static void clearUrl(String streamId) { ... }

  static RecordingDetail? getSummary(String streamId) { ... }
  static void saveSummary(String streamId, RecordingDetail d) { ... }  // TTL: 10 dk
}
```

Cache erişimi (okuma/yazma) `RecordingDetailNotifier` içinde, Screen dışında gerçekleşir — View katmanı `CacheService`'e doğrudan bağımlı değildir.

### 8.7 OTA Localization — ARB Anahtarları

Tüm yeni UI stringleri ARB dosyalarına eklenir, uygulama kodunda hardcode yazılmaz.

**Eklenecek ARB anahtarları (TR/EN/AR/RU):**

| Key | TR | EN |
|-----|----|----|
| `proToolMyRecordingsTitle` | Canlı Yayınlarım | My Recordings |
| `proToolMyRecordingsDesc` | Yayınlarını izle ve satış detaylarını gör | Watch your streams and view sales details |
| `recordingStatusPreparing` | Hazırlanıyor... | Preparing... |
| `recordingStatusWatch` | İzle | Watch |
| `recordingStatusExpired` | Süresi Doldu | Expired |
| `recordingStatusExpiresIn` | Son: {duration} | Expires in: {duration} |
| `recordingDetailAuctions` | Müzayedeler | Auctions |
| `recordingDetailDirectSales` | Direkt Satışlar | Direct Sales |
| `recordingDetailGifts` | Hediyeler | Gifts |

**Deploy akışı (ADR §1.7):**
1. 4 ARB dosyasına key-value ekle
2. `git commit + push`
3. VPS'te: `git pull && python3 scripts/sync_translations.py && sudo teqlif-restart`
4. Uygulama güncellemesi gerekmez — OTA değişiklik

---

## 9. Yapılacaklar

Öncelik sırası: **Altyapı → Backend Migration → Backend Yeni → Mobile**

### A. Altyapı

- [ ] **cluster.yaml:** `transfer_window_end_utc: 8` → `5` (05:00 UTC = 08:00 TR)
- [ ] **node2:** `minio_backup` timer 04:00 → 05:30 UTC; transfer bittikten 30 dk sonra, 09:00 TR öncesi
- [ ] **encoder.py:** acil modda (`free_gb < 10`) `mc cp` komutuna `--limit-upload 30M` ekle; LiveKit bant genişliğini koru
- [ ] **encoder.py:** `_MAX_PARALLEL` — 8+ çekirdekli node'larda 2'ye çıkarılabilir; önce LiveKit + FFmpeg eş zamanlı yük testi yapılmalı

### B. Backend — recording_enabled Migrasyonu

- [ ] Alembic: `live_streams.recording_enabled` kolonu kaldır (her `op.execute()` ayrı — asyncpg kuralı)
- [ ] `StartStreamRequest` şemasından `recording_enabled` kaldır
- [ ] `start_stream` use case'den `recording_enabled` parametresi kaldır
- [ ] `RecordingManager._sync_recordings()`: `AND ls.recording_enabled = TRUE` filtresi kaldır
- [ ] `GET /streams/{id}/recording`: `recording_enabled` kontrolü → PRO kontrolü ile değiştir

### C. Backend — Yeni Özellikler

- [ ] **encoder.py:** encode sonrası `ffprobe` ile `duration_secs` hesapla ve DB'ye yaz (şu an daima NULL)
- [ ] **`GetMyRecordingsQuery`:** use-case sınıfı yaz; Router `/recordings/my`'dan çağırır
- [ ] **`GetRecordingSummaryQuery`:** use-case sınıfı yaz; auctions + bids + direct_sales + gifts birleştirir
  - `Bid` tablosuna `auction_id` kolonu ekle (Alembic) — heuristik yerine migration tercih edilir
  - `GiftEvent` verisi ilk kez endpointte expose edilir
- [ ] **`ErrorMapper`:** `RECORDING_NOT_FOUND`, `RECORDING_EXPIRED`, `RECORDING_NOT_AVAILABLE` kodlarını ekle

### D. Mobile

- [ ] `pro_hub_screen.dart`: "Yayın & Kitle" accordion'ına 4. `_ToolCard` ekle (`ConsumerWidget` — `loc.t()` kullanır)
- [ ] `RecordingRepository`: `getMyRecordings()`, `getRecordingUrl()`, `getRecordingSummary()` metodları; `Result<T>` döner
- [ ] `RecordingsCacheService`: §8.6 üç katman, `CacheService` wrapper'ı
- [ ] `MyRecordingsNotifier` + `MyRecordingsScreen`: §8.3 MVVM yapısı
- [ ] `RecordingDetailNotifier` + `RecordingDetailScreen`: §8.4 MVVM yapısı; 403 recovery notifier'da
- [ ] `RecordingCard`: status chip + countdown (`Timer.periodic`) — pure View, ViewModel'den veri alır
- [ ] Bottom modal bileşenleri: müzayede / direkt satış / hediyeler — profil navigasyonlu; ayrı `ConsumerWidget`
- [ ] ARB anahtarları: §8.7 tablosundaki tüm key'ler TR/EN/AR/RU'ya eklenir
- [ ] ARB deploy: `sync_translations.py` çalıştır (uygulama güncellemesi gerekmez)

---

## 10. Bilinen Kısıtlar

| Kısıt | Açıklama |
|-------|----------|
| Transfer gecikme | Yayın gece bitiyor, disk ≥ 15 GB ise 03:00 UTC'ye kadar bekleniyor |
| Tek encode slot | `_MAX_PARALLEL = 1` (CPU koruma) — prime time'da sıra oluşabilir; node3/4 yükü dağıtır |
| Agent restart | `recording` durumundaki kayıtlar `failed`'a çekilir; yeniden kayıt başlamaz |
| Transfer retry | `mc cp` hatası → `encoded`'a geri döner + Telegram alert; bir sonraki pencerede tekrar |
| `duration_secs` NULL | `ffprobe` çalışmıyor; `GET /recordings/my`'dan önce encoder.py güncellenmeli |
| Satır silme yok | `archived` final durum; `cleanup_actions.sh` mevcut değil |
| `Bid.auction_id` yok | Teklifler müzayede bazında gruplanamıyor; migration gerekiyor |
| GiftEvent endpoint yok | Hediye verisi DB'de var ama hiçbir API'de dönmüyor |
| Presigned TTL | URL 1 saat geçerli; oynatma sırasında expire olursa 403 recovery ViewModel'de tetiklenir |
| Staging | node5'te ayrı `teqlif-staging` bucket, aynı pipeline |
