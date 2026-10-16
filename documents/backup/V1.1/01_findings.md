# Chat Dump Güvenilirliği — Planlama Bulguları

**Tarih:** 2026-10-16  
**Kapsam:** `finalize_stream` → `_dump_chat_to_db` hata senaryosu analizi; kayıp önleme tasarım kararları.

---

## 1. Mevcut Akış

```
finalize_stream(stream, db)
  ├─ 1. Redis istatistik snapshot (viewer_count, peak)
  ├─ 2. DB: stream.is_live=False, status=ENDED, ended_at=now
  ├─ 3. DB: açık viewer seanslarını kapat
  ├─ 4. _dump_chat_to_db(stream, db)      ← kayıp noktası
  ├─ 5. LiveKit room sil (idempotent)
  ├─ 6. redis.delete(... chat_key ...)    ← chat key burada siliniyor
  ├─ 7. Pro insights cache invalidation
  └─ 8. WS STREAM_ENDED broadcast
```

### Kayıp mekanizması

`_dump_chat_to_db` tüm istisnaları iç `try/except` ile yutuyor, `None` dönüyor.  
`finalize_stream` bu sonucu kontrol etmiyor; step 6 chat key'i her koşulda siliyor.

DB bağlantı hatası, connection pool tükenmesi veya asyncpg zaman aşımı → dump sessizce başarısız → key silinir → mesajlar kalıcı olarak kaybolur.

### Çağıran yollar

| Çağıran | Tetikleyici |
|---------|-------------|
| `EndStreamCommand` | Host "Yayını Bitir" butonu |
| `force_close_stream` (worker) | `cleanup_stale_streams_task` (her 2 dk) |
| `force_close_stream` (webhooks) | LiveKit `room_finished` webhook |
| `admin_end_stream` (admin router) | Admin paneli |

### Redis key özellikleri

| Parametre | Değer |
|-----------|-------|
| Key | `chat:{stream_id}:messages` — `chat_utils.py::chat_key()` ile üretilir |
| Tip | Redis List |
| TTL | 24 saat (her yeni mesajda yenilenir; yayın bitince yenilenmez) |
| LTRIM tavan | 2000 mesaj |

### Mevcut kontroller

| Kontrol | Durum |
|---------|-------|
| Hata loglanıyor | ✅ `logger.error(..., exc_info=True)` |
| Sentry'e gidiyor | ❌ |
| Retry | ❌ |
| Başarı/başarısızlık dönüyor | ❌ daima `None` |
| Chat key dump başarısızsa korunuyor | ❌ step 6 her zaman siliyor |

---

## 2. Tasarım Kararları

### 2.1 `dump_chat_to_db(stream_id, db)` — imza ve idempotency

Fonksiyon `stream` nesnesi yerine `stream_id: int` alır. `stream.id` dışında hiçbir alan kullanılmıyor; worker için gereksiz DB round-trip ortadan kalkar. `_` prefix kaldırılır — worker da çağıracak.

**İdempotency:** `stream_chat_messages` tablosunda `id BIGSERIAL PRIMARY KEY` dışında unique constraint yok. `on_conflict_do_nothing` conflict hiçbir zaman görmez. Ağ partition senaryosunda commit DB'ye yazılır ancak Python exception alır → fonksiyon `False` döner → retry çalışır → `on_conflict_do_nothing` duplicate'ı engelleyemez.

Çözüm: aynı transaction içinde önce stream'in mevcut satırlarını sil, ardından yeniden yaz:

```python
from sqlalchemy import delete as sa_delete

await db.execute(sa_delete(StreamChatMessage).where(StreamChatMessage.stream_id == stream_id))
await db.execute(pg_insert(StreamChatMessage).values(rows))
await db.commit()
```

DELETE + INSERT tek transaction'da atomic — commit başarısız olursa ikisi de rollback olur. Retry her zaman temiz bir slate'e yazar. Migration gerekmez.

**Boş chat başarı sayılır.** Mesaj yoksa ya da tüm satırlar parse edilemezse `True` dönülür:

```python
if not raw_messages:
    return True
if not rows:
    return True
```

Fonksiyon `bool` döner: `True` başarı, `False` hata. Hata durumunda `db.rollback()` çağrılır (session'ı temiz bırakır), ardından `capture_exception` ile Sentry'e gönderilir.

### 2.2 `finalize_stream` step 6 koşullu hale gelir

```python
dump_ok = await dump_chat_to_db(stream.id, db)
```

Step 6'da chat key yalnızca `dump_ok is True` iken silinir. Diğer sekiz key etkilenmez:

```python
base_keys = [
    f"live:viewers:{stream.id}",
    f"live:peak_viewers:{stream.id}",
    f"live:viewer_set:{stream.id}",
    f"live:room_to_stream:{stream.room_name}",
    f"live:pip_viewer_set:{stream.id}",
    f"live:host_reconnect:{stream.id}",
    f"stream:stats:{stream.id}",
    f"stream:likes:{stream.id}",
]
if dump_ok:
    base_keys.append(chat_key(stream.id))
await redis.delete(*base_keys)
```

Dump başarısız olursa key Redis'te kalır ve 24 saatlik TTL devreye girer — retry task bu pencereyi kullanır.

### 2.3 Retry task: DB sorgusu, `chat_key()` import'u

Retry task hangi stream'lerin dump'ının başarısız olduğunu **DB'den** öğrenir:

```sql
SELECT id FROM live_streams
WHERE ended_at > NOW() - INTERVAL '2 hours'
  AND ended_at < NOW() - INTERVAL '5 minutes'
```

Key'i oluştururken string literal değil `chat_utils.py::chat_key()` import'u kullanılır:

```python
from app.use_cases.chat.chat_utils import chat_key

key = chat_key(stream_id)
if await redis.exists(key):
    ok = await dump_chat_to_db(stream_id, db)
    if ok:
        await redis.delete(key)
```

**Pencere neden 2 saat:** 2 saat + 30 dk cron = en fazla 4 retry. 2 saat sonra cron bu stream'i sorgu kapsamından çıkarır; Redis key 24 saatlik TTL'inin geri kalanında Redis'te kalır ve expire olur.

### 2.4 `_agent_ok` ve watchdog registry

V2.1'de tüm cron task'lar tamamlandığında `_agent_ok(ctx, "<task_name>")` çağırır. Aksi halde watchdog görevi takip edemez ve varsayılan 60 dk aralıkla hatalı uyarı üretir.

`deploy/scale/V2.1/teqlif-agent/modules/watchdog.py` → `_CONTINUOUS_REGISTRY` güncellenir:

```python
"retry_failed_chat_dumps_task": 30,   # dakika cinsinden beklenen periyot
```

### 2.5 Retry task `WorkerSettings`'e eklenir

`WorkerSettings` (node1 `teqlif-worker.service`) ve staging worker (node5 `teqlif-worker-staging.service`) — `functions` listesi ve cron (her 30 dk).  
`WorkerSettingsCritical`'a eklenmez: chat dump batch iş, kritik kullanıcı bildirimlerini bloklamaz.

---

## 3. Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `backend/app/use_cases/streams/stream_finalizer.py` | `_dump_chat_to_db` → `dump_chat_to_db(stream_id, db) -> bool`; DELETE+INSERT; `capture_exception`; boş chat `True`; step 4 sonucu al; step 6 koşullu |
| `backend/app/worker.py` | `retry_failed_chat_dumps_task` + `WorkerSettings.functions` + cron (her 30 dk) |
| `deploy/scale/V2.1/teqlif-agent/modules/watchdog.py` | `_CONTINUOUS_REGISTRY`'e `"retry_failed_chat_dumps_task": 30` |

---

## 4. ADR Uyum Kontrol Listesi

| Kural | Durum |
|-------|-------|
| `asyncio.create_task+sleep` iş etkili geçişlerde yasak | ✅ ARQ cron task |
| `dump_chat_to_db` tek sorumluluk: sadece dump yapar | ✅ |
| Worker Redis key formatına değil `chat_key()` fonksiyonuna bağımlı | ✅ |
| Boş mesaj hata sayılmıyor | ✅ `True` dönülür |
| DELETE+INSERT atomic, migration yok | ✅ |
| Retry fırtınası engellendi (2 saatlik pencere = maks 4 retry) | ✅ |
| `_agent_ok` + `_CONTINUOUS_REGISTRY` kaydı | ✅ |
| Bulkhead: `WorkerSettings` (default), kritik worker değil | ✅ |
