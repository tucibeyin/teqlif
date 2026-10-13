# Stream Replay — V1.4 Bulgular ve Plan

**Tarih:** 2026-10-13  
**Kapsam:** Host ekranı deneyiminin kayıt oynatımına taşınması — synchronized replay overlay  
**Önceki sürüm:** `documents/stream/V1.3/01_findings.md` (kayıt altyapısı, durum makinesi)

---

## 0. Uygulama İlkeleri

| Prensip | Kaynak | Bu Feature'a Etkisi |
|---------|--------|---------------------|
| **Clean Architecture** | ADR | Router → UseCase → Model; View katmanı DB/Redis bilmez |
| **MVVM** | ADR §8 | Replay pozisyonu View'da (UI state), event verisi ViewModel'de |
| **OTA Localization** | ADR §1 | Tüm overlay stringleri ARB'a eklenir, `loc.t()` ile tüketilir |
| **Cache Taksonomisi** | ADR §9 | Replay verisi tamamlanmış stream için değişmez; LIFECYCLE 24 saat (kayıt `expires_at`'e kadar) |
| **Deployment Workflow** | ADR §13 | Local → push → pull → `sudo teqlif-restart` |
| **asyncpg Kuralı** | `feedback_alembic_asyncpg.md` | Her SQL komutu ayrı `op.execute()` — multi-statement yasak |
| **Uploads URL** | `feedback_uploads_url.md` | `kUploadsHost` ile oluşturulur, `kBaseHost + /uploads/` değil |

---

## 1. Sorun

Video kaydı `livekit-rtc` gizli abone ile alınır (ADR §19). Kayıt yalnızca video akışını içerir; host ekranındaki chat, teklifler, hediyeler, satın almalar görünmez. Bu veri DB'de bulunmakta olup replay sırasında video pozisyonuyla senkronize edilebilir.

### Neden "host ekranı kaydı" değil?

| Yaklaşım | Neden elendi |
|----------|-------------|
| iOS ReplayKit / Android MediaProjection | Ayrı process/permission, pil/termal yük, `video-in-video` kalite kaybı |
| FFmpeg burn-in (post-process) | Ekstra CPU + depolama; sonradan UI değiştirilemez; V2.1 presigned mimarisine zor entegre |
| **Data replay overlay** ✓ | Video dokunulmaz; veri DB'de zaten var; interaktif (profil tıklama); host cihazına sıfır ek yük |

---

## 2. Mevcut Mimari Analizi

### 2.1 `stream_recordings` tablosu

| Kolon | Önem |
|-------|------|
| `recording_started_at` | Video T=0 referansı — `livekit-rtc` egress başlangıcı. `live_streams.started_at`'ten farklı (birkaç saniyelik LiveKit egress gecikmesi) |
| `duration_secs` | Toplam kayıt süresi |
| `status` | `available` olmadan oynatma URL'i yok |

`recording_started_at`, `GET /recordings/my`'da döner ama **`GET /streams/{id}/recording-summary`'de dönmez** — bu temel eksik.

### 2.2 Event timestamp durumu

Her event tipi yalnızca wall-clock `created_at` / `sent_at` içerir. `offset_secs` kolonu hiçbir tabloda yok — query time'da hesaplanacak:

```sql
EXTRACT(EPOCH FROM (event.created_at - :recording_started_at)) AS offset_secs
```

| Event | Tablo | Timestamp | Stream Bağlantısı |
|-------|-------|-----------|-------------------|
| Teklif | `bids` | `created_at` | `stream_id` FK |
| Satın alma | `direct_sale_orders` | `created_at` | `direct_sales.stream_id` |
| Hediye | `gift_events` | `sent_at` | `stream_id` FK |
| Chat | Redis list | `created_at` (dict içinde) | `chat:{stream_id}:messages` key |
| İzleyici | `live_stream_viewers` | `joined_at`, `left_at` | `stream_id` FK |

### 2.3 Chat — kritik kısıtlar

```python
# chat_commands.py + chat_utils.py
_MAX_HISTORY = 50        # sadece son 50 mesaj Redis'te tutulur
TTL = 24 * 3600          # her mesaj yazılışında yenilenir
```

**Sorun 1 — `_MAX_HISTORY = 50`:** Uzun yayınlarda binlerce mesaj atılır; Redis'te yalnızca son 50 kalır. "Yayın sonunda DB'ye yaz" yaklaşımı ancak bu limit büyütülürse anlamlıdır.

**Sorun 2 — Kalıcılık yok:** `stream_chat_messages` tablosu mevcut değil. Mesajlar yalnızca Redis'te yaşar; 24 saat sonra kalıcı olarak kaybolur.

**`finalize_stream()` davranışı:** `stream_finalizer.py` `chat:{stream_id}:messages` key'ini silmez — 24 saat TTL'e bırakır. Bu, "stream bitince dump" için yeterli pencere sağlar ama `_MAX_HISTORY` limiti hâlâ geçerlidir.

### 2.4 `get_recording_summary.py` mevcut durum

`GetRecordingSummaryQuery.execute()` şu anda şunları döndürür:

- `stream`: `started_at`, `ended_at` — ama **`recording_started_at` yok**
- `auctions`: `duration_minutes` (hesaplanmış) — ama `started_at`/`ended_at` ham değerleri yok
- `bids`: `created_at` (wall-clock) — offset yok
- `direct_sales`: `started_at`, `ended_at` var ✓
- `orders`: `created_at` — offset yok
- `gifts.events`: `sent_at` — offset yok
- **Chat: hiç yok**

### 2.5 Flutter model durumu

`RecordingStreamMeta`: `startedAt`, `endedAt` var — `recordingStartedAt` **yok**  
`RecordingBid`, `RecordingGiftEvent`: `createdAt`/`sentAt` var — `offsetSecs` **yok**  
`RecordingChatMessage`: **sınıf yok**  
`RecordingDetail.chatMessages`: **alan yok**

Video player: `VideoPlayerController` + `ChewieController` mevcut. `position` listener yok — replay overlay altyapısı kurulmamış.

---

## 3. Mimari Karar: Yayın Sonunda DB'ye Yaz (Yol A)

### Seçenekler karşılaştırması

| | Yol A — Yayın sonunda dump | Yol B — Her mesajda fire-and-forget INSERT |
|--|---------------------------|-------------------------------------------|
| DB yükü | Sadece yayın bitişinde, tek batch | Her mesajda async INSERT |
| Veri bütünlüğü | Crash → `finalize_stream` çağrılmazsa chat kaybolur (24h TTL penceresi var) | Garantili — her mesaj DB'de |
| Kod karmaşıklığı | `_MAX_HISTORY` büyütme + finalize dump | `_persist_and_publish` + DB insert |
| `_MAX_HISTORY` sorunu | **Zorunlu olarak büyütülmeli** | Gerek yok |

**Karar: Yol A** — `_MAX_HISTORY` 2000'e çıkarılır + `finalize_stream` dump.

Gerekçe: Replay yalnızca yayın bittikten sonra erişilebilir; canlı yayın sırasında DB write baskısı gereksiz. `_MAX_HISTORY = 2000` × ~250 byte = ~500 KB/stream Redis RAM (node1: 11 GB, node5: 7.8 GB — ihmal edilebilir).

---

## 4. Uygulama Planı

### Katman 1 — Backend

#### 4.1 Migration: `zzzzzo_stream_chat_messages.py`

```sql
CREATE TABLE stream_chat_messages (
    id          BIGSERIAL PRIMARY KEY,
    stream_id   INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    username    VARCHAR(100) NOT NULL,
    avatar_url  TEXT,
    content     TEXT NOT NULL,
    is_host     BOOLEAN NOT NULL DEFAULT FALSE,
    is_mod      BOOLEAN NOT NULL DEFAULT FALSE,
    is_hidden   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_stream_chat_messages_stream_id_created_at
    ON stream_chat_messages (stream_id, created_at);
```

**Neden `offset_secs` kolon değil:** Sabit değer saklamak anti-pattern. `recording_started_at` değişebilir (re-encode senaryosu). Query time'da hesaplamak her zaman tutarlı.

**asyncpg kuralı:** Her `op.execute()` ayrı satır — tek multi-statement string yasak.

**Yaşam döngüsü kuralı:** `stream_chat_messages` satırları video kaydıyla birlikte silinir. ARQ `janitor` görevi şu koşulda temizler:

```sql
DELETE FROM stream_chat_messages
WHERE stream_id IN (
    SELECT ls.id FROM live_streams ls
    WHERE ls.ended_at < NOW() - INTERVAL '30 days'
);
```

`ON DELETE CASCADE` ile `live_streams` silindiğinde otomatik temizlenir; ARQ görevi erken temizlik için ek güvencedir. Video `archived` olunca (transferred_at + 2 gün MinIO ILM, archived_at + 15 gün DB) replay zaten çalışmaz — chat satırlarının daha uzun yaşamasının işlevsel karşılığı yoktur.

#### 4.2 Chat persistence: `_MAX_HISTORY` + finalize dump

**`chat_commands.py` + `chat_utils.py`:**
```python
_MAX_HISTORY = 2000   # 50'den 2000'e
```

**`stream_finalizer.py` — `_dump_chat_to_db` helper:**
```python
async def _dump_chat_to_db(stream: LiveStream, db: AsyncSession, redis) -> None:
    key = f"chat:{stream.id}:messages"
    raw_messages = await redis.lrange(key, 0, -1)
    if not raw_messages:
        return

    messages = [json.loads(m) for m in raw_messages]
    rows = [
        {
            "stream_id":  stream.id,
            "user_id":    msg.get("user_id"),
            "username":   msg.get("username", ""),
            "avatar_url": msg.get("profile_image_url"),
            "content":    msg.get("content", ""),
            "is_host":    msg.get("is_host", False),
            "is_mod":     msg.get("is_mod", False),
            "is_hidden":  msg.get("is_hidden", False),
            "created_at": msg.get("created_at"),
        }
        for msg in messages
    ]
    # Tek multi-row INSERT — N ayrı roundtrip değil, tek statement
    await db.execute(
        text("""
            INSERT INTO stream_chat_messages
                (stream_id, user_id, username, avatar_url, content,
                 is_host, is_mod, is_hidden, created_at)
            VALUES
                (:stream_id, :user_id, :username, :avatar_url, :content,
                 :is_host, :is_mod, :is_hidden, :created_at)
            ON CONFLICT DO NOTHING
        """),
        rows,
    )
    await db.commit()
```

`finalize_stream()` içinde DB commit öncesi çağrılır. Aynı fonksiyon `cleanup_stale_streams_task` (ARQ, 2 dk cron) ve `force_close_stream` içinden de çağrılmalıdır — zombie yayınlarda chat verisinin 24 saat TTL ile kaybolmasını önler. Redis delete bloğuna `f"chat:{stream.id}:messages"` eklenir (dump sonrası temizle).

#### 4.3 `get_recording_summary.py` güncellemeleri

**`_fetch_stream`** — `recording_started_at` ekle:
```sql
(SELECT recording_started_at FROM stream_recordings
 WHERE stream_id = :stream_id AND status = 'available'
 ORDER BY created_at DESC LIMIT 1) AS recording_started_at
```

**`_fetch_bids_for_auction`** — `offset_secs` ekle:
```sql
EXTRACT(EPOCH FROM (b.created_at - :recording_started_at)) AS offset_secs
```

**`_fetch_orders_for_sale`** — `offset_secs` ekle:
```sql
EXTRACT(EPOCH FROM (dso.created_at - :recording_started_at)) AS offset_secs
```

**`_fetch_gifts`** — `offset_secs` ekle:
```sql
EXTRACT(EPOCH FROM (ge.sent_at - :recording_started_at)) AS offset_secs
```

**Yeni `_fetch_chat_messages(stream_id, recording_started_at)`:**
```sql
SELECT user_id, username, avatar_url, content, is_host, is_mod,
       EXTRACT(EPOCH FROM (created_at - :rec_start)) AS offset_secs,
       created_at
FROM stream_chat_messages
WHERE stream_id = :stream_id
  AND is_hidden = FALSE
ORDER BY created_at ASC
```

**Response değişiklikleri:**
- `stream.recording_started_at` eklendi
- Her event'e `offset_secs: float | null` eklendi
- `chat_messages: list` eklendi

**Cache TTL:** Yayın bittikten sonra bu veri değişmez. `RecordingsCacheService.saveSummary` TTL'i 10 dk yerine `recording_expires_at - now()` (max 24 saat) olarak hesaplanır. `recording_expires_at` null ise 24 saat sabit kullanılır.

### Katman 2 — Flutter: Model (`recording.dart`)

**`RecordingStreamMeta`:** `recordingStartedAt: DateTime?` ekle

**`RecordingBid`:** `offsetSecs: double?` ekle

**`RecordingOrder`** (yeni sınıf — `RecordingDirectSale.orders` içinde):
```dart
class RecordingOrder {
  final int userId;
  final String username;
  final String? avatarUrl;
  final int quantity;
  final double unitPrice;
  final double? offsetSecs;
  final DateTime? createdAt;
}
```

**`RecordingGiftEvent`:** `offsetSecs: double?` ekle

**Yeni `RecordingChatMessage`:**
```dart
class RecordingChatMessage {
  final int? userId;
  final String username;
  final String? avatarUrl;
  final String content;
  final bool isHost;
  final bool isMod;
  final double? offsetSecs;
  final DateTime? createdAt;
}
```

**`RecordingDetail`:** `chatMessages: List<RecordingChatMessage>` ekle

### Katman 3 — Flutter: ViewModel (`recording_detail_view_model.dart`)

`RecordingDetailState`'e ekle:
```dart
final bool replayEnabled;  // recordingStartedAt != null && chatMessages.isNotEmpty
```

Pozisyon state'i View'da tutulur (ADR §8 — UI state = View sorumluluğu). ViewModel sadece `replayEnabled` flag'ini hesaplar.

### Katman 4 — Flutter: View (`recording_detail_screen.dart`)

**Pozisyon listener** — `_initPlayer` sonrası:
```dart
double _replayPosSecs = 0.0;

void _initPlayer(String url) {
  // ... mevcut kod ...
  _vpCtrl!.addListener(_onPlayerTick);
}

void _onPlayerTick() {
  if (!mounted) return;
  final pos = _vpCtrl!.value.position.inSeconds.toDouble();
  if ((pos - _replayPosSecs).abs() >= 1.0) {
    setState(() => _replayPosSecs = pos);
  }
}

@override
void dispose() {
  _vpCtrl?.removeListener(_onPlayerTick);
  // ... mevcut dispose ...
}
```

`>= 1.0` kontrolü: her frame'de `setState` çağrısını engeller — yalnızca saniye değiştiğinde rebuild.

**Birleşik event listesi** — video altına yerleştirilir:

```dart
// Tüm event tiplerini tek listeye flatten et, offsetSecs'e göre sırala
List<_ReplayEvent> get _visibleEvents {
  final all = <_ReplayEvent>[
    for (final a in detail.auctions)
      for (final b in a.bids)
        if (b.offsetSecs != null && b.offsetSecs! <= _replayPosSecs)
          _ReplayEvent.bid(b, a.itemName),
    for (final ds in detail.directSales)
      for (final o in ds.orders)
        if (o.offsetSecs != null && o.offsetSecs! <= _replayPosSecs)
          _ReplayEvent.order(o, ds.title),
    for (final ge in detail.gifts.events)
      if (ge.offsetSecs != null && ge.offsetSecs! <= _replayPosSecs)
        _ReplayEvent.gift(ge),
    for (final cm in detail.chatMessages)
      if (cm.offsetSecs != null && cm.offsetSecs! <= _replayPosSecs)
        _ReplayEvent.chat(cm),
  ]..sort((a, b) => a.offsetSecs.compareTo(b.offsetSecs));
  return all;
}
```

**`_ReplayFeed` widget** — `ScrollController` + auto-scroll to bottom:

```
┌──────────────────────────────────────┐
│   Video Player (Chewie)              │
├──────────────────────────────────────┤
│   Anlık Akış                ⊙ canlı │  ← loc.t('replayFeedTitle')
│  ─────────────────────────────────  │
│  [🔨] 02:34  Ali  ₺250 teklif       │
│  [💬] 02:36  Veli  "Güzel, ne fiyat"│
│  [🎁] 02:38  Ayşe  Kalp × 3        │
│  [🛍] 02:40  Zeynep  iPhone 2 adet  │
│  ─────────────────────────────────  │
├──────────────────────────────────────┤
│   (mevcut özet kartları)             │
└──────────────────────────────────────┘
```

| Event tipi | İkon | Renk |
|-----------|------|------|
| Chat | `Icons.chat_bubble_outline` | `AppColors.textSecondary` |
| Teklif | `Icons.gavel` | `Colors.amber[700]` |
| Hediye | `Icons.card_giftcard` | `Color(0xFFEC4899)` |
| Satın alma | `Icons.shopping_bag_outlined` | `Color(0xFF6366F1)` |

### ARB Anahtarları (5 dil: TR/EN/AR/DE/RU)

| Key | TR | EN |
|-----|----|----|
| `replayFeedTitle` | Anlık Akış | Live Feed |
| `replayEventBid` | Teklif | Bid |
| `replayEventGift` | Hediye | Gift |
| `replayEventPurchase` | Satın Alma | Purchase |
| `replayEventChat` | Chat | Chat |
| `replayNoEventsYet` | Henüz etkinlik yok | No events yet |

---

## 5. Uygulama Sırası

```
1.  Backend — Alembic migration: zzzzzo_stream_chat_messages (tablo + index + yaşam döngüsü kuralı)
2.  Backend — _MAX_HISTORY: chat_commands.py + chat_utils.py  50 → 2000
3.  Backend — stream_finalizer.py: _dump_chat_to_db (bulk insert) + Redis delete
4.  Backend — cleanup_stale_streams_task (ARQ): _dump_chat_to_db hook'u eklenir
5.  Backend — force_close_stream.py: _dump_chat_to_db hook'u eklenir
6.  Backend — get_recording_summary.py: recording_started_at + offset_secs + chat_messages
7.  git push → node1 + node5: git pull + sudo teqlif-restart
8.  Flutter — recording.dart: model güncellemeleri
9.  Flutter — recording_detail_view_model.dart: replayEnabled state
10. Flutter — recording_detail_screen.dart: pozisyon listener + _ReplayFeed
11. Flutter — RecordingsCacheService: summary TTL → recording_expires_at'e göre dinamik (max 24 saat)
12. ARB dosyaları: 6 yeni key × 5 dil
13. flutter analyze
14. git push → node1 + node5: sudo teqlif-restart (sync_translations otomatik çalışır)
```

---

## 6. Riskler ve Kararlar

| Risk | Karar |
|------|-------|
| Stream crash → `finalize_stream` çağrılmaz → chat kaybolur | `_dump_chat_to_db` üç noktadan çağrılır: `finalize_stream`, `force_close_stream`, `cleanup_stale_streams_task` (ARQ 2 dk cron). Zombie yayın 2 dk içinde yakalanır ve dump tetiklenir. |
| `recording_started_at` NULL (encoding tamamlanmamış) | `replayEnabled = false`; feed gizlenir. `recordingStartedAt == null` kontrolü ile guard. |
| `offset_secs` negatif (mesaj recording başlamadan atıldı) | `max(0.0, offsetSecs)` — sıfırdan itibaren gösterilir. |
| `_MAX_HISTORY = 2000` yetmezse (çok aktif yayın) | Yol B'ye geçiş kolay: `_persist_and_publish` içine tek satır `asyncio.create_task(db_insert(msg))` eklenir. |
| `_vpCtrl` listener her frame tetiklenir | `>= 1.0` saniye farkı kontrolü ile setState frekansı sınırlandı. |
| Yüzlerce event varsa `_visibleEvents` O(N) | Yayın süresi max 24 saat, event sayısı pratikte < 5000. Kabul edilebilir. |

---

## 7. Kapsam Dışı (Bu Versiyon)

| Özellik | Sebep |
|---------|-------|
| İzleyici giriş/çıkış replay | `live_stream_viewers` verisi mevcut ama yayın özetinde UI değeri düşük |
| Hediye animasyonu replay | Gift event timestamp var; animasyon varlıkları ayrı tasarım çalışması gerektirir |
| Chat arama / filtre | Mevcut `TeqSearchField` ile eklenebilir; V1.5'e bırakıldı |
| Viewer-side replay (host dışı) | ADR §5.3: izleyici erişimi kapsam dışı |
