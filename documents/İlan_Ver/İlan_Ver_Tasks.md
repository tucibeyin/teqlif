# İlan Ver — Görev Listesi

**Plan:** `İlan_Ver_Plan.md`  
**Ekran:** `mobile/lib/screens/create_listing_screen.dart`  
**Backend:** `backend/app/routers/listings.py`, `backend/app/services/ml/llm_service.py`

---

## FAZ 1 — Buton Etiketi (ARB + Sync)

- [ ] **T01** — ARB key'lerini güncelle (4 dil)
  - `aiDescButton`: "AI ile Açıklama Yaz" → "Yapay Zeka ile Açıklama Yaz"
  - `aiDescUnavailable`: "AI açıklama servisi..." → "Yapay Zeka açıklama servisi..."
  - `app_tr.arb`, `app_en.arb`, `app_ar.arb`, `app_ru.arb`

- [ ] **T02** — VPS sync
  - `cd /var/www/teqlif.com/backend && python scripts/sync_translations.py && sudo systemctl restart teqlif`

---

## FAZ 2 — Buton Davranışı Hizalama

- [ ] **T03** — `_AiDescButton` widget'ından `enabled` parametresini kaldır
  - `_AiDescButton`: `enabled` prop silinir, button her zaman aktif görünür
  - `build()` içinde `active` değişkeni kaldırılır; gradient her zaman gösterilir
  - `onTap: active ? onTap : null` → `onTap: loading ? null : onTap`

- [ ] **T04** — `_buildDescriptionSection`'da `enabled: _aiReady` kaldır
  - `_AiDescButton(loading: _aiDescLoading, enabled: _aiReady, ...)` → `enabled` satırı silinir

- [ ] **T05** — Hata/uyarı davranışı AD §3 uyum kontrolü
  - Ekranda `showErrorSnackbar(context, ...)` veya `ErrorDisplay` kullanımı kalmadığını doğrula
  - `_fetchAiDescription` içindeki tüm hata dallarının `TeqSnackBar` veya `handleError` kullandığını kontrol et

---

## FAZ 3 — Zengin AI Açıklama

- [ ] **T06** — Flutter: `_fetchAiDescription` request body'sini genişlet
  - Mevcut: `title`, `category`, `condition`, `price`, `location`
  - Eklenecek: `subcategory`, `district`, `extra_fields`
  - `_extraValues` + `_extraMultiValues` (join ile) birleştirilip `extra_fields` dict'e dönüştürülür
  - Boş dict gönderilmez (`if` guard ile)

- [ ] **T07** — Backend: `GenerateDescriptionRequest` genişlet
  - `subcategory: Optional[str] = None`
  - `district: Optional[str] = None`
  - `extra_fields: Optional[dict[str, str]] = None`

- [ ] **T08** — Backend: `generate_listing_description_stream` imzasını güncelle
  - Yeni parametreler: `subcategory`, `district`, `extra_fields`
  - `_build_prompt`'a geçilir

- [ ] **T09** — Backend: `_build_prompt` genişlet
  - `subcategory` varsa `user_lines`'a ekle
  - `extra_fields` varsa okunabilir liste olarak ekle (TR label'larla: marka → Marka, yil → Yıl, km → Kilometre vb.)
  - `district` varsa `location` ile birleştir: "Kadıköy, İstanbul"
  - Boş/None değerler sessizce atlanır

- [ ] **T10** — Manuel test
  - Otomobil ilanı: tüm extra field dolu → açıklamada marka/model/yıl/km geçiyor mu?
  - Kitap ilanı: extra field yok → açıklama bozulmuyor mu?
  - Extra field boş iken (subcategory yok) → mevcut davranışla aynı mı?

- [ ] **T11** — Commit + push + VPS deploy
  - `git pull && sudo systemctl restart teqlif`
