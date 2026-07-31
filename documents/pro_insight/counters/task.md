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
| T-CNT-05 | listings.py blast TuciTransaction type düzelt (spend_lead_gen → spend_blast) | F-BLAST-01 | Yüksek | ✅ Tamamlandı |
| T-CNT-06 | Reaktivasyon → created_at sıfırlanmasını Insights sorgularında ele al | F-REACT-01 | Yüksek | ✅ Tamamlandı |
| T-CNT-07 | boost: listings tablosuna is_boosted computed alanı veya view ekle | F-BOOST-02 | Orta | ✅ Tamamlandı |
| T-CNT-08 | ai_price embed başarısız → kredi tüketme, hata döndür | F-AIPRICE-04 | Orta | ✅ Tamamlandı |
| T-CNT-09 | LLM fallback (Groq→Gemini) Flutter'a bildirilsin | F-AIDESC-03 | Düşük | ✅ Tamamlandı |
| T-CNT-10 | 30 gün reaktivasyon penceresini Pro Hub sayacında göster | F-REACT-03 | Düşük | ✅ Tamamlandı |

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

### T-CNT-05 — Blast TuciTransaction Type ✅ Tamamlandı

- `leads.py` → `"spend_lead_gen"` → `"spend_blast"`
- `listings.py` → `"spend_mass_notification"` → `"spend_blast"`

Her iki blast yolu artık TUCi geçmişinde aynı type ile görünüyor.

---

### T-CNT-06 — Reaktivasyon created_at Sıfırlanması ✅ Tamamlandı

Seçenek B uygulandı: `reactivated_at` alanı eklendi.

- `listing.py`: `reactivated_at: Optional[datetime]` alanı eklendi
- `toggle_listing.py`: `listing.created_at = now()` → `listing.reactivated_at = now()`
- `search.py` (3 yer): `order_by(Listing.created_at.desc())` → `order_by(COALESCE(reactivated_at, created_at).desc())`
- `analytics.py` hot_leads: aynı COALESCE sıralaması

**VPS'te çalıştırılması gereken SQL:**
```sql
ALTER TABLE listings ADD COLUMN IF NOT EXISTS reactivated_at TIMESTAMPTZ;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_listings_reactivated_at
  ON listings (reactivated_at DESC NULLS LAST)
  WHERE status = 'active';
```

---

### T-CNT-07 — is_boosted Entegrasyonu ✅ Tamamlandı

- `analytics.py` hot_leads: `AdCampaign` import edildi; aktif kampanya listing_id'leri `boost_ids` set'ine alındı
- hot_leads response'a `is_boosted: bool` eklendi
- `pro_insights_screen.dart` `_HotLeadCard`: `is_boosted == true` ise mor "Öne Çıkarıldı" badge gösteriliyor
- ARB: `hotLeadBoosted` TR/EN/AR/RU eklendi

---

### T-CNT-08 — AI Price Embed Başarısız → Kredi Tüketme ✅ Tamamlandı

**Dosya:** [backend/app/routers/analytics.py](../../../../backend/app/routers/analytics.py#L528)

ARQ job tamamlandıktan sonra embedding boyutu doğrulanıyor:
```python
if not embedding or len(embedding) < 64:
    raise ServiceException(code="AI_SERVICE_EMBEDDING_INVALID")
```
Geçersiz embedding Redis'e yazılmıyor, kredi tüketilmiyor.

---

### T-CNT-09 — LLM Fallback Flutter'a Bildir ✅ Tamamlandı

- `llm_service.py`: Groq path başında `yield "__META_groq__"`, Gemini path başında `yield "__META_gemini__"` eklendi
- `listings.py`: SSE loop'da `__META_*__` sentinel algılandığında `{"meta": {"model": "groq/gemini"}}` SSE event'i gönderiliyor
- `create_listing_screen.dart`: `meta.model == "gemini"` ise `aiDescFallbackNotice` snackbar gösteriliyor
- ARB: `aiDescFallbackNotice` TR/EN/AR/RU eklendi

---

### T-CNT-10 — 30 Gün Penceresi Pro Hub'da ✅ Tamamlandı

- `analytics.py` `/reactivation-credits`: `within_window_count` — son 30 günde `reactivated_at IS NOT NULL` olan aktif ilanlar sayılıyor; response'a eklendi
- `pro_hub_screen.dart`: `CreditItemModel`'e `extraHintBuilder` alanı eklendi; reactivation kartında `within_window_count > 0` ise yeşil "X ilanın 30 gün penceresi içinde" gösteriliyor
- ARB: `proReactivationWindowHint` TR/EN/AR/RU eklendi
