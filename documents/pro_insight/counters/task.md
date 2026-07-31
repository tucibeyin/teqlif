# Pro Insight Kredi Sayaçları — Task Listesi

**Son güncelleme:** 31 Temmuz 2026  
**Bağlantılı:** `pro_insight_counters_architecture.md`

---

## Özet Tablo

| ID | Başlık | Kaynak | Öncelik | Durum |
|----|--------|--------|---------|-------|
| T-CNT-01 | Pro Hub fallback limitleri düzelt (boost:3, ai_price:6, react:3) | F-CROSS-01 | Kritik | ✅ Tamamlandı |
| T-CNT-02 | TuciTransaction type ayrıştır: spend_ai_price / spend_ai_desc | F-AIPRICE-02, F-AIDESC-02 | Yüksek | ✅ Tamamlandı |
| T-CNT-03 | SSE krediyi ilk chunk'ta say (bağlantı kopma koruması) | F-AIDESC-01 | Kritik | ✅ Tamamlandı |
| T-CNT-04 | Lead blast'a 24 saatlik cooldown ekle | F-BLAST-02 | Orta | ✅ Tamamlandı |
| T-CNT-05 | listings.py blast TuciTransaction type düzelt (spend_lead_gen → spend_blast) | F-BLAST-01 | Yüksek | Bekliyor |
| T-CNT-06 | Reaktivasyon → created_at sıfırlanmasını Insights sorgularında ele al | F-REACT-01 | Yüksek | Bekliyor |
| T-CNT-07 | boost: listings tablosuna is_boosted computed alanı veya view ekle | F-BOOST-02 | Orta | Bekliyor |
| T-CNT-08 | ai_price embed başarısız → kredi tüketme, hata döndür | F-AIPRICE-04 | Orta | Bekliyor |
| T-CNT-09 | LLM fallback (Groq→Gemini) Flutter'a bildirilsin | F-AIDESC-03 | Düşük | Bekliyor |
| T-CNT-10 | 30 gün reaktivasyon penceresini Pro Hub sayacında göster | F-REACT-03 | Düşük | Bekliyor |

---

## Tamamlananlar

### T-CNT-01 — Pro Hub Fallback Limitleri ✅ Tamamlandı

**Dosya:** [mobile/lib/screens/pro_hub_screen.dart](../../../../mobile/lib/screens/pro_hub_screen.dart#L819)

| Özellik | Eski | Yeni |
|---------|------|------|
| boost `defaultPremiumLimit` | 5 | 3 |
| boost `defaultFreeLimit` | 1 | 0 |
| ai_price `defaultPremiumLimit` | 20 | 6 |
| reactivation `defaultPremiumLimit` | 5 | 3 |

---

### T-CNT-02 — TuciTransaction Type Ayrıştırma ✅ Tamamlandı

**analytics.py** — ai_price işlemleri:
- `"spend_ai"` → `"spend_ai_price"`

**listings.py** — ai_desc işlemleri:
- `"spend_ai"` → `"spend_ai_desc"` (2 yer)

Kullanıcı TUCi geçmişinde artık hangi özelliği kullandığını görebilir.

---

### T-CNT-03 — SSE Kredi İlk Chunk'ta ✅ Tamamlandı

**Dosya:** [backend/app/routers/listings.py](../../../../backend/app/routers/listings.py#L615)

**Eski davranış:** Tüm stream bittikten sonra `if text_generated:` bloğunda kredi sayılırdı. Bağlantı kopunca kredi tüketilmeden kullanıcı metni alırdı.

**Yeni davranış:** `not text_generated` koşulunda (ilk chunk'ta) kredi sayılıyor. LLM çalıştığı ve kullanıcının içerik aldığı doğrulanmış oluyor. `__LLM_ERROR__` durumunda kredi tüketilmiyor.

---

### T-CNT-04 — Lead Blast Cooldown ✅ Tamamlandı

**Dosya:** [backend/app/routers/leads.py](../../../../backend/app/routers/leads.py#L157)

`send_blast` endpoint'inin başına `MassNotificationCampaign` sorgusu eklendi: son 24 saat içinde bu kullanıcının herhangi bir blast kampanyası varsa `CooldownException` (429) fırlatılıyor.

---

## Bekleyen Tasklar

### T-CNT-05 — leads.py Blast TuciTransaction Type

**Dosya:** [backend/app/routers/leads.py](../../../../backend/app/routers/leads.py#L285)

```python
# MEVCUT:
transaction_type="spend_lead_gen"  # leads.py blast'ta

# ÖNERİLEN — tüm blast işlemleri için tutarlı:
transaction_type="spend_blast"
```

**listings.py** (`spend_mass_notification`) da `"spend_blast"` olmalı ki raporlama tutarlı olsun.

---

### T-CNT-06 — Reaktivasyon created_at Sıfırlanması

**Dosya:** [backend/app/use_cases/listings/commands/toggle_listing.py](../../../../backend/app/use_cases/listings/commands/toggle_listing.py#L22)

**Sorun:** Pencere dışı reaktivasyonda `listing.created_at = now()` yapılıyor. Pro Insights sorgularında (`hot_leads`, `price_intel`) `created_at` filtresi kullanılıyor — reaktive edilen eski ilan "yeni" gibi davranıyor.

**Seçenek A — `original_created_at` alanı ekle:**
```sql
ALTER TABLE listings ADD COLUMN original_created_at TIMESTAMPTZ;
-- Mevcut kayıtlar: original_created_at = created_at
```
Pro Insights sorgularında `created_at` yerine `original_created_at` kullan.

**Seçenek B — reactivated_at alanı ekle:**
```sql
ALTER TABLE listings ADD COLUMN reactivated_at TIMESTAMPTZ;
```
`created_at` dokunulmaz, sadece `reactivated_at` güncellenir. Feed sıralaması için `COALESCE(reactivated_at, created_at)` kullanılır.

**Not:** DB migration gerekiyor — SQL VPS'e verilmeli.

---

### T-CNT-07 — is_boosted DB Alanı / View

**Dosya:** [backend/app/models/listing.py](../../../../backend/app/models/listing.py)

```sql
-- PostgreSQL view (migration gerektirmez):
CREATE OR REPLACE VIEW listings_with_boost AS
SELECT l.*,
       CASE WHEN ac.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_boosted,
       ac.id AS active_campaign_id
FROM listings l
LEFT JOIN ad_campaigns ac ON ac.listing_id = l.id AND ac.status = 'active';
```

Alternatif: `listings` tablosuna `is_boosted boolean GENERATED ALWAYS AS (...)` computed column (PG 12+).

---

### T-CNT-08 — AI Price Embed Başarısız → Kredi Tüketme

**Dosya:** [backend/app/routers/analytics.py](../../../../backend/app/routers/analytics.py#L476)

```python
# Mevcut akış: embed timeout/fail → düşük kalite sonuç → kredi tüketilir
# Önerilen:
try:
    embedding = await _get_or_generate_embedding(title, desc, category, timeout=15)
except EmbeddingTimeoutError:
    raise ServiceException(code="EMBEDDING_UNAVAILABLE",
                           message="Fiyat analizi geçici olarak kullanılamıyor.")
# embedding başarılı olduktan SONRA pipeline devam eder ve kredi sayılır
```

---

### T-CNT-09 — LLM Fallback Flutter'a Bildir

**Dosya:** [backend/app/services/ml/llm_service.py](../../../../backend/app/services/ml/llm_service.py)  
**Dosya:** [mobile/lib/screens/create_listing_screen.dart](../../../../mobile/lib/screens/create_listing_screen.dart#L295)

```python
# SSE stream'e model bilgisi ekle (ilk chunk veya meta event):
yield f"data: {json.dumps({'meta': {'model': 'groq-primary' | 'gemini-fallback'}})}\n\n"
```

Flutter bu bilgiyi kullanarak kalite uyarısı gösterebilir (opsiyonel).

---

### T-CNT-10 — 30 Gün Penceresi Pro Hub'da

**Dosya:** [backend/app/routers/analytics.py](../../../../backend/app/routers/analytics.py#L413) — `/reactivation-credits`  
**Dosya:** [mobile/lib/screens/pro_hub_screen.dart](../../../../mobile/lib/screens/pro_hub_screen.dart#L846)

Reactivation credits endpoint'i `within_window_count` dönebilir (son 30 günde ücretsiz reaktive edilen ilan sayısı). Pro Hub bu bilgiyi sayacın altında "Bu ay X ücretsiz pencere kullanıldı" şeklinde gösterebilir.
