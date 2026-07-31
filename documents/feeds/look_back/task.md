# Geri Bak Feed — Task Listesi

**Son güncelleme:** Temmuz 2026  
**Bağlantılı:** `findings.md`, `look_back_architecture.md`

---

## Özet

| ID | Başlık | Kaynak | Öncelik | Durum |
|----|--------|--------|---------|-------|
| T-LB-01 | VPS deploy + ClickHouse subcategory doğrulama | F-03 | Kritik | Bekliyor |
| T-LB-02 | ARB anahtarlarını VPS'e sync'le | — | Kritik | Bekliyor |
| T-LB-03 | Pro Insights metrik doğrulama | F-04 | Kritik | Bekliyor |
| T-LB-11 | hes_spike'ı bid_hesitation'a kısıtla | F-11 | Yüksek | ✅ Tamamlandı |
| T-LB-12 | argMax top_signal mantığını düzelt | F-12 | Yüksek | ✅ Tamamlandı |
| T-LB-13 | _loadHesitated stream onError ekle | F-13 | Orta | ✅ Tamamlandı |
| T-LB-14 | /hesitated ClickHouse hata loglama | F-14 | Orta | ✅ Tamamlandı |
| T-LB-04 | not_interested TTL eşitleme | F-07 | Orta | ✅ Tamamlandı |
| T-LB-05 | hesitated_shelf_tap Thompson Sampling | F-09 | Orta | ✅ Tamamlandı |
| T-LB-06 | Dismiss → TeqToast | F-10 | Düşük | ✅ Tamamlandı |
| T-LB-15 | retarget_task penceresini 14 güne genişlet | F-16 | Düşük | ✅ Tamamlandı |
| T-LB-16 | VPS: ClickHouse subcategory sütunu doğrulama | F-15 | Düşük | Bekliyor |
| T-LB-07 | price_point semantik ayrımı (araştırma) | F-08 | Araştırma | Bekliyor |
| T-LB-08 | hesitated:{uid} ML feature değerlendirmesi | F-01 | Araştırma | Bekliyor |
| T-LB-09 | Shelf shimmer loading | — | Araştırma | Bekliyor |
| T-LB-10 | Subcategory-level diversity | — | Araştırma | Bekliyor |

---

## Kritik — VPS Deploy Gerektiren

### T-LB-01 — VPS Deploy + ClickHouse subcategory Doğrulama

**Kaynak:** F-03 düzeltmesi, commit `75fcf5d8`  
**Bağımlılık:** T-LB-02 ile birlikte yapılmalı

Deploy:
```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

Doğrulama (ClickHouse'da):
```sql
SELECT subcategory, count()
FROM user_events
WHERE timestamp >= now() - INTERVAL 1 DAY
  AND event_type IN ('bid_hesitation', 'detail_dwell')
GROUP BY subcategory
ORDER BY count() DESC
LIMIT 20;
-- Boş olmayan subcategory değerleri bekleniyor.
-- Tümü '' geliyorsa worker flush'u kontrol et.
```

---

### T-LB-02 — ARB Anahtarlarını VPS'e Sync'le

**Commit:** `75fcf5d8`'de eklenen 4 yeni ARB anahtarı VPS DB'sine henüz yansıtılmadı.

```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

Yeni anahtarlar (4 dilde): `hesitatedPriceDrop`, `hesitatedPriceNearOffer`, `hesitatedOffers`, `hesitatedDismissed`

---

### T-LB-03 — Pro Insights Metrik Doğrulama

**Kaynak:** F-04 düzeltmesi (Temmuz 2026)  
**Doğrulama:**

```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://api.teqlif.com/api/analytics/pro-insights/{listing_id}
# avg_detail_dwell_seconds > 0, dwells > 0 bekleniyor.
```

---

## Yüksek Öncelik

### T-LB-11 — hes_spike'ı Yalnızca bid_hesitation İçin Say

**Kaynak:** F-11  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py)

**Değişiklik:** `analytics.py`'de `hes_spike` counter'ını `bid_hesitation` ile `detail_dwell` yazımından ayır. `hesitated:{uid}` set'i ikisi için yazılmaya devam etmeli; yalnızca spike sayacı kısıtlanmalı.

```python
# MEVCUT (L157-180) — her iki sinyal spike'ı artırıyor:
if payload.interaction_type in ("bid_hesitation", "detail_dwell"):
    await redis.sadd(hes_key, ...)
    spike_count = await redis.incr(spike_key)
    ...

# ÖNERİLEN — set yazımı her ikisi için, spike yalnızca bid_hesitation:
if payload.interaction_type in ("bid_hesitation", "detail_dwell"):
    await redis.sadd(hes_key, ...)

if payload.interaction_type == "bid_hesitation":          # ← yalnızca bid
    spike_count = await redis.incr(spike_key)
    if spike_count == 1:
        await redis.expire(spike_key, 86400)
    if spike_count == 3:
        # notify_hot_listing_task(...)
```

Bildirim metni bu şekilde doğru olacak: gerçekten teklif niyeti olan kullanıcılar sayılıyor.

---

### T-LB-12 — argMax top_signal Mantığını Intent-Aware Yap

**Kaynak:** F-12  
**Dosya:** [backend/app/routers/feed.py](../../../backend/app/routers/feed.py)

**Değişiklik:** ClickHouse sorgusunda `argMax(event_type, timestamp)` tabanlı sıralamayı `countIf(event_type = 'bid_hesitation') > 0` bazlı sıralamaya geçir.

```sql
-- MEVCUT:
SELECT
    item_id,
    argMax(event_type, timestamp)   AS top_signal,
    MAX(timestamp)                  AS last_seen,
    argMax(price_point, timestamp)  AS last_price_point
FROM user_events
...
ORDER BY
    multiIf(top_signal = 'bid_hesitation', 0, 1),
    last_seen DESC

-- ÖNERİLEN:
SELECT
    item_id,
    countIf(event_type = 'bid_hesitation') > 0  AS has_bid_intent,
    argMax(event_type, timestamp)                AS top_signal,
    MAX(timestamp)                               AS last_seen,
    argMaxIf(price_point, timestamp,
             event_type = 'bid_hesitation')      AS bid_price_point,
    argMaxIf(price_point, timestamp,
             event_type = 'detail_dwell')        AS dwell_price_point
FROM user_events
...
ORDER BY
    has_bid_intent DESC,
    last_seen DESC
```

Bu değişiklik F-08 (price_point anlamsal çakışması) sorununu da kısmen giderir: `bid_price_point` ve `dwell_price_point` artık ayrı sütunlarda.

**Not:** Python tarafında `price_point_map` ve signal bayrak hesapları da güncellenmeli.

---

## Orta Öncelik

### T-LB-13 — _loadHesitated Stream onError Ekle

**Kaynak:** F-13  
**Dosya:** [mobile/lib/screens/home_screen.dart](../../../mobile/lib/screens/home_screen.dart#L123)

```dart
// MEVCUT:
ApiService.get<List<dynamic>>(...).listen((data) {
  if (mounted) setState(() => _hesitatedListings = data);
});

// ÖNERİLEN:
ApiService.get<List<dynamic>>(...).listen(
  (data) {
    if (mounted) setState(() => _hesitatedListings = data);
  },
  onError: (e) {
    if (mounted) handleError(e, ref.read(localizationProvider));
  },
);
```

`handleError` import'u `home_screen.dart`'ta zaten mevcut — `error_helper.dart` kullanılıyor.

---

### T-LB-14 — /hesitated Endpoint ClickHouse Hata Loglama

**Kaynak:** F-14  
**Dosya:** [backend/app/routers/feed.py](../../../backend/app/routers/feed.py#L239)

```python
# MEVCUT:
    except Exception:
        return []

# ÖNERİLEN:
    except Exception as ch_exc:
        logger.warning("[Feed/Hesitated] ClickHouse sorgu hatası: %s", ch_exc)
        return []
```

`return []` korunabilir (SWR cache ile uyumlu), ancak log kaydı eklenmeli. İzleme ve debug için kritik.

---

### T-LB-04 — not_interested TTL Eşitleme

**Kaynak:** F-07  
**Dosya:** [backend/app/routers/feed.py](../../../backend/app/routers/feed.py#L95)

```python
# MEVCUT (L95):
await redis.expire(key, 7 * 86400)   # POST /not-interested

# ÖNERİLEN — 14 güne eşitle:
await redis.expire(key, 14 * 86400)  # dismiss ile aynı politika
```

Migration gerekmez; mevcut key'lerin TTL'leri doğal olarak değişmez — yalnızca sonraki EXPIRE yazımı etkiler.

---

### T-LB-05 — hesitated_shelf_tap Thompson Sampling Listesine Ekle

**Kaynak:** F-09  
**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L515)

```python
# listing_events filtresi — "hesitated_shelf_tap" ekle:
r["interaction_type"] in (
    "listing_offer_submit", "listing_chat_open", "listing_favorite",
    "listing_share", "listing_like", "detail_dwell",
    "listing_view", "listing_impression", "listing_skip",
    "listing_unfavorite",
    "hesitated_shelf_tap",    # ← EKLE
)
```

Ağırlık tavsiyesi: `detail_dwell` ile aynı veya daha yüksek (`>= 2.5`) — yeniden tıklama güçlü bir yeniden-ilgi sinyalidir.

Etkilenen ağırlık tablosu — `worker.py`'deki `WHEN event_type = 'detail_dwell' THEN 2.5` satırından sonra:
```python
WHEN event_type = 'hesitated_shelf_tap' THEN 2.5
```

---

## Düşük Öncelik

### T-LB-06 — Dismiss Snackbar → TeqToast

**Kaynak:** F-10  
**Dosya:** [mobile/lib/screens/home_screen.dart](../../../mobile/lib/screens/home_screen.dart#L520)

```dart
// MEVCUT:
if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(loc.t('hesitatedDismissed')), duration: const Duration(seconds: 2)),
  );
}

// ÖNERİLEN (AD §2.7 uyumlu):
TeqToast.success(loc.t('hesitatedDismissed'));
```

`mounted` check gerekmez — `TeqToast` context-free.

---

### T-LB-15 — hesitation_retarget_task Penceresini 14 Güne Genişlet

**Kaynak:** F-16  
**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L2908)

```python
# MEVCUT:
WHERE event_type  = 'bid_hesitation'
  AND timestamp  >= now() - INTERVAL 7 DAY

# ÖNERİLEN — feed penceresiyle eşitle:
  AND timestamp  >= now() - INTERVAL 14 DAY
```

Retarget dedup key TTL de 7→14 güne güncellenmeli:
```python
await redis.setex(dedup_key, 14 * 86400, "1")  # 7 gün → 14 gün
```

---

### T-LB-16 — PG user_interactions subcategory Sütunu Araştırma

**Kaynak:** F-15  
**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L429), [backend/app/models/analytics.py](../../../backend/app/models/analytics.py)

1. `UserInteraction` modelinde `subcategory` kolonu var mı kontrol et.
2. Varsa → `pg_rows` dict'ine ekle.
3. Yoksa → migration karar ver (Alembic + VPS'te `alembic upgrade head`).
4. Şu an PG'den subcategory okuyan bir sorgu yoksa bu task ertelenebilir.

---

## Araştırma / Gelecek

### T-LB-07 — price_point Semantik Ayrımı

**Kaynak:** F-08  
T-LB-12 (argMax düzeltmesi) tamamlandıktan sonra değerlendir — o task ayrı sütunları (`bid_price_point`, `dwell_price_point`) zaten getiriyor.

---

### T-LB-08 — hesitated:{uid} Set'ini ML Feature Olarak Değerlendir

**Kaynak:** F-01  
Set şu an `hes_spike` için tutulmakta. Potansiyel kullanımlar:
- Real-time "Sana Özel" feed'inden hesitate edilen ilanları dışla (tekrar gösterme)
- Oturum içi anlık ilgi vektörü seed'i

---

### T-LB-09 — Shelf Shimmer Loading

Şu an liste boşken shelf hiç render edilmiyor. Yükleme sırasında skeleton göstermek UX'i iyileştirir. `_hesitatedLoading` bayrağı + shimmer widget gerektiriyor.

---

### T-LB-10 — Subcategory-Level Diversity

Şu an kategori başına max 3. Subcategory (alt kategori) bazında da kısıt eklenebilir (örn. max 2). `feed.py`'ye `subcat_counts` dict ve PostgreSQL `listings` sorgusuna `subcategory` JOIN gerektiriyor.
