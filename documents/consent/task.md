# KVKK Rıza Akışı — Görev Listesi

> Referans plan: `documents/consent/plan.md`
> Strateji: Madde 9/6/b (sözleşmesel zorunluluk) → birincil mekanizma | Madde 9/4/c (bulut sağlayıcı sözleşmesi) → idari tamamlayıcı

---

## AŞAMA 1 — Teknik

### 1. Veritabanı

- [x] **DB-1** `users` tablosuna migration yaz (`zzzzi_add_cross_border_consent.py`) — model güncellendi
- [x] **DB-2** Migration VPS'te çalıştırıldı ve doğrulandı (`zzzzh_age_confirmed -> zzzzi_cross_border_consent`)

---

### 2. Backend

- [x] **BE-1** `POST /api/auth/register` — `cross_border_consent: bool` eklendi (schema + router)
- [x] **BE-2** `GET /api/auth/me/consent` — `ConsentOut` response ile mevcut durum döndürülüyor
- [x] **BE-3** `PATCH /api/auth/me/consent` — rıza verme ve geri alma işleniyor
- [ ] **BE-4** Her rıza değişikliği audit log'a yazılıyor (kim, ne zaman, ne yönde)
- [x] **BE-5** Kayıt sırasında `cross_border_consent: false` ile kayıt kabul ediliyor (zorunlu değil)

---

### 3. Localization (ARB)

> Dört dil: `app_tr.arb`, `app_en.arb`, `app_ru.arb`, `app_ar.arb`

- [x] **L10N-1** `consentCrossBorderTitle` — dört dilde eklendi
- [x] **L10N-2** `consentCrossBorderRiskNote` — dört dilde eklendi
- [x] **L10N-3** `consentPrivacyNoticeLinkLabel` — dört dilde eklendi
- [x] **L10N-4** `consentPrivacyNoticeTitle` — dört dilde eklendi
- [x] **L10N-5** `consentPrivacyNoticeBody` — dört dilde eklendi (Madde 10 gerekleri karşılandı)
- [x] **L10N-6** `consentRevokeTitle` — dört dilde eklendi
- [x] **L10N-7** `consentRevokeConfirm` — dört dilde eklendi
- [x] **L10N-8** `consentStatusActive` — dört dilde eklendi (`{date}` parametreli)
- [x] **L10N-9** `consentStatusNone` — dört dilde eklendi
- [x] **L10N-10** Dört dil için metinler yazıldı (TR / EN / RU / AR)
- [x] **L10N-11** `sync_translations.py` çalıştırıldı — 4 dilde 2975 key, 11900 satır upsert

---

### 4. Mobile — ConsentNoticeModal Widget

> Bağımsız widget; kayıt ekranı ve ayarlar ekranından açılabilir.

- [x] **MOB-1** `ConsentNoticeModal` widget'ı oluşturuldu (`mobile/lib/widgets/consent_notice_modal.dart`)
- [x] **MOB-2** Modal içeriği ARB key'lerinden okunuyor (`consentPrivacyNoticeTitle`, `consentPrivacyNoticeBody`)
- [x] **MOB-3** Modal scroll edilebilir, kapat butonu ve drag handle var
- [x] **MOB-4** Madde 10 gerekleri ARB metninde karşılanıyor (veri sorumlusu, amaç, Virginia/ABD, Madde 11, e-posta)

---

### 5. Mobile — Kayıt Ekranı

- [x] **MOB-5** Kayıt formunun altına aydınlatma linki eklendi → tıklayınca `ConsentNoticeModal` açılıyor
- [x] **MOB-6** Yurt dışı rıza checkbox'ı eklendi — isteğe bağlı, kayıt engellenmiyor
- [x] **MOB-7** Checkbox işaretlendiğinde expandable risk özeti otomatik açılıyor
- [x] **MOB-8** `AuthService.register()` ve `RegisterViewModel.register()` `crossBorderConsent` parametresi eklendi
- [x] **MOB-9** Kayıt isteğine `cross_border_consent` alanı payload'a eklendi

---

### 6. Mobile — Ayarlar Ekranı

- [x] **MOB-10** `profilePrivacySection` bölümüne consent `ListTile` eklendi
- [x] **MOB-11** `_loadConsentStatus()` ile `GET /auth/me/consent` çağrılıyor, durum gösteriliyor
- [x] **MOB-12** Tile'a tıklayınca `ConsentNoticeModal` açılıyor; Switch ile rıza ver/geri al
- [x] **MOB-13** Rıza geri alırken `_showRevokeConfirm()` onay diyaloğu gösteriliyor
- [x] **MOB-14** `PATCH /auth/me/consent` başarılıysa state ve UI güncelleniyor

---

### 7. Test

- [ ] **TEST-1** Checkbox işaretli → kayıt → DB'de `cross_border_consent_given=true` doğrulandı
- [ ] **TEST-2** Checkbox işaretsiz → kayıt → DB'de `cross_border_consent_given=false`, kayıt başarılı
- [ ] **TEST-3** Ayarlar'dan rıza verme → DB güncellendi, UI güncellendi
- [ ] **TEST-4** Ayarlar'dan rıza geri alma → DB güncellendi, `revoked_at` dolduruldu
- [ ] **TEST-5** Rıza metni versiyonu değiştirildi → eski rızalar `v1`, yeni kullanıcılar `v2` — karışma yok
- [ ] **TEST-6** `ConsentNoticeModal` tüm dillerde açılıyor ve içerik doğru

---

## AŞAMA 2 — İdari

> Teknik aşama tamamlandıktan sonra yapılacak. Kod değişikliği gerektirmez.

- [ ] **ADM-1** KVKK Kurulu'nun yayımladığı standart sözleşme şablonu indirildi
- [ ] **ADM-2** Şablon bulut sağlayıcıya iletildi ve imzalandı
- [ ] **ADM-3** İmza tarihinden itibaren 5 iş günü içinde KVKK Kurumu'na bildirim yapıldı
- [ ] **ADM-4** VERBIS kaydı güncellendi:
  - Yurt dışı aktarım: Virginia, ABD (US-EAST-VA)
  - Hukuki dayanak: Madde 9/4/c (standart sözleşme)

---

## Özet Tablo

| Alan | Görev Sayısı | Durum |
|------|-------------|-------|
| Veritabanı | 2 | Tamamlandı |
| Backend | 5 | 4 tamamlandı, 1 opsiyonel (audit log) |
| Localization | 11 | Tamamlandı |
| Mobile — Modal | 4 | Tamamlandı |
| Mobile — Kayıt | 5 | Tamamlandı |
| Mobile — Ayarlar | 5 | Tamamlandı |
| Test | 6 | Bekliyor |
| İdari | 4 | Bekliyor |
| **Toplam** | **42** | **32 tamamlandı** |
