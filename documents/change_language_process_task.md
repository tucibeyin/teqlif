# Dil Değiştirme Süreç Yönetimi

## Problem

`localeProvider.setLocale()` çağrıldığında state **anında** güncelleniyor
(toggle yeni dile geçiyor), ama `LocalizationService` dil paketini henüz
indirmedi. Toggle yeni dili gösterirken UI hâlâ eski dilde kalıyor.
Cache'te varsa hemen düzeliyor; cache'te yoksa fetch bitene kadar
eski dil devam ediyor.

## Hedef Akış

```
Kullanıcı toggle'a basar
        │
        ▼
_displayedLang = newLang (toggle optimistic move)
_isSwitching = true (blur + spinner)
        │
        ▼
LocalizationService.switchLanguage(newLang)
  ├─ Cache'te var? → anında pack'i yükle → true döner
  └─ Cache yok   → API fetch
       ├─ Başarılı → pack'i cache'le, state'i güncelle → true döner
       └─ Başarısız → state değişmez → false döner
        │
   ┌────┴─────┐
   ▼          ▼
Başarılı    Başarısız
   │          │
setLocale   _displayedLang = prevLang (toggle geri döner)
(persist +  TeqToast.error(langSwitchFailed)
 backend)   _isSwitching = false
   │
TeqToast.success(langSwitchSuccess)
_isSwitching = false
```

## Mimari Kararlar

- **`switchLanguage()` → `Future<bool>`**: Caller başarı/başarısız bilgisini alır.
- **`localeProvider.setLocale()` sadece başarı sonrası çağrılır**: Persist + backend sync yalnızca pack hazır olduğunda tetiklenir.
- **Lokal `_displayedLang` state**: Toggle'ı localeProvider'dan bağımsız kontrol eder. localeProvider değişene kadar toggle kendi state'iyle çalışır.
- **`LanguageSwitchOverlay` widget**: Blur + spinner mantığı reusable — Login ve Settings ekranı aynı widget'ı kullanır.
- **localeProvider listener guard**: `_currentLang` zaten eşleşiyorsa `load()` tekrar tetiklenmez (gereksiz rebuild önlenir).

---

## FAZ 1 — ARB Keys

- [x] **T01** — 4 ARB dosyasına (`app_tr`, `en`, `ar`, `ru`) yeni keyleri ekle ✅

  | Key | TR | EN | AR | RU |
  |-----|----|----|----|-----|
  | `langSwitching` | Dil yükleniyor… | Loading language… | جارٍ تحميل اللغة… | Загрузка языка… |
  | `langSwitchSuccess` | Dil değiştirildi | Language changed | تم تغيير اللغة | Язык изменён |
  | `langSwitchFailed` | Dil değiştirilemedi. Bağlantınızı kontrol edin. | Failed to change language. Check your connection. | فشل تغيير اللغة. تحقق من اتصالك. | Не удалось изменить язык. Проверьте соединение. |

---

## FAZ 2 — LocalizationService

- [x] **T02** — `_fetchAndCache()` → `Future<bool>` döndürsün ✅
  - Başarıda `return true`, HTTP/network hatasında `return false`
  - `state = TranslationPack(...)` sadece `true` durumunda

- [x] **T03** — `switchLanguage(String lang) → Future<bool>` metodu ekle ✅
  - Cache'te varsa: anında pack yükle → `_currentLang = lang`, `state` güncelle, `_checkStale` fire-and-forget → `return true`
  - Cache'te yoksa: `_fetchAndCache()` çağır → başarıda `_currentLang = lang`, `return true`; başarısızda `_currentLang` değişmez, `return false`

- [x] **T04** — `localeProvider` listener'a guard ekle ✅
  - `if (next.languageCode == _currentLang && !state.isEmpty) return;`
  - `setLocale()` başarı sonrası çağrıldığında gereksiz ikinci `load()` tetiklenmez

---

## FAZ 3 — Reusable Widget

- [x] **T05** — `lib/widgets/language_switch_overlay.dart` oluştur ✅
  ```
  LanguageSwitchOverlay(isVisible: bool, child: Widget)
    Stack:
      child
      if (isVisible) → Positioned.fill
        BackdropFilter(blur σ=6)
        ColoredBox(black 25% opacity)
        Center → CircularProgressIndicator(white)
  ```

---

## FAZ 4 — Login Ekranı

- [x] **T06** — Lokal state ekle ✅
  ```dart
  late String _displayedLang;   // initState'te localeProvider'dan oku
  bool _isSwitching = false;
  ```

- [x] **T07** — `_onLangChange(String newLang)` metodu ✅
  - `_isSwitching = true`, `_displayedLang = newLang`
  - `await switchLanguage(newLang)` → başarı/başarısız yönetimi
  - Başarıda: `setLocale()` → `TeqToast.success(langSwitchSuccess)`
  - Başarısızda: `_displayedLang = prevLang` → `TeqToast.error(langSwitchFailed)`

- [x] **T08** — SegmentedButton güncelle ✅
  - `selected: {_displayedLang}` (artık localeProvider değil)
  - `onSelectionChanged: (s) => _onLangChange(s.first)`

- [x] **T09** — `LanguageSwitchOverlay` ile Scaffold.body'yi sar ✅

---

## FAZ 5 — Settings Ekranı (profile_screen.dart)

- [x] **T10** — Login ekranıyla aynı pattern'i uygula ✅
  - `_SettingsContentState` ya da `_ProfileScreenState` içinde `_displayedLang` + `_isSwitching`
  - `_onLangChange()` metodu
  - SegmentedButton `selected` → `_displayedLang`
  - `LanguageSwitchOverlay` wrap

---

## FAZ 6 — Backend Sync & Verify

- [x] **T11** — `dart analyze` → 0 error ✅ (2 pre-existing warning, 2 info)

- [ ] **T12** — Yeni 3 ARB key'ini DB'ye sync et (VPS'te):
  ```
  git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
  ```
  3 key × 4 dil = 12 yeni satır

- [ ] **T13** — Commit + push

---

## Test Senaryoları (Manuel)

| Senaryo | Beklenen |
|---------|---------|
| Cache'te olan dile geç | Spinner yok, anında değişir |
| Cache'te olmayan dile geç (normal net) | Spinner → pack yükle → success toast |
| Cache'te olmayan dile geç (uçak modu) | Spinner → timeout → error toast → toggle geri döner |
| Yükleme sırasında tekrar tıkla | Yok sayılır (`_isSwitching` guard) |
| Başarılı değişim sonrası uygulama kapat/aç | Seçilen dil korunur (SharedPreferences) |

---

## Durum

**Başlangıç:** 2026-07-26  
**Son güncelleme:** 2026-07-26  
**Tamamlanan task:** 11 / 13 (T12 ve T13 manuel/VPS)
