# Mobile Navigation — Bulgular

_Son güncelleme: 2026-10-19_

---

## 1. Mobil → Web Yönlendirme Haritası

| URL | Dosya | Açılış modu | Durum |
|-----|-------|-------------|-------|
| `/kullanim-sartlari.html` | `kullanim-sartlari.html` | `externalApplication` | ✓ |
| `/gizlilik-politikasi` *(`.html` yok)* | `gizlilik-politikasi.html` | `externalApplication` | ✓ nginx `try_files` yakalar |
| `/support.html` | `support.html` | `externalApplication` | ✓ |
| `/pro-plan.html` | `pro-plan.html` | `inAppWebView` | ⚠️ Bakınız §2 |
| `/ilan/{id}` | `ilan.html` | share (paylaşım linki) | ✓ 2026-10-19 düzeltildi |
| `/profil/{username}` | `profil.html` | share (paylaşım linki) | ✓ 2026-10-19 düzeltildi |
| `/yayin/{id}` | `yayin.html` | share (paylaşım linki) | ✓ 2026-10-19 düzeltildi |

### Çağrılan dosyalar

| Ekran / widget | URL |
|----------------|-----|
| `profile_screen.dart:2141` | `/support.html` |
| `profile_screen.dart:2162` | `/kullanim-sartlari.html` |
| `profile_screen.dart:2174` | `/gizlilik-politikasi` |
| `auth/register_screen.dart:299` | `/kullanim-sartlari.html` |
| `pro_hub_screen.dart:472,730` | `/pro-plan.html` |
| `listing_analytics_screen.dart:499` | `/pro-plan.html` |
| `market_intelligence_screen.dart:387` | `/pro-plan.html` |
| `widgets/pro_paywall_overlay.dart:87` | `/pro-plan.html` |
| `listing_detail_screen.dart:1257` | `/ilan/{id}` (share) |
| `public_profile_screen.dart:212` | `/profil/{username}` (share) |
| `widgets/live/viewer_top_bar.dart:127` | `/yayin/{streamId}` (share) |

---

## 2. Sorunlar ve Notlar

### 2.1 `/pro-plan.html` — inAppWebView dead end

Dört farklı ekran/widget bu sayfayı `LaunchMode.inAppWebView` ile açıyor. Sayfadaki
"Hemen Pro Ol" butonu (`pro-plan.js:141`) herhangi bir satın alma akışı başlatmıyor;
yalnızca toast gösteriyor:

> *"Pro abonelik altyapısı çok yakında! Hazır olduğunda bildirim alacaksınız."*

Web sayfası native IAP (StoreKit / Google Play Billing) akışını tetikleyemez.
IAP implement edildiğinde bu sayfanın ya deep link ile uygulamayı açması ya da
kaldırılıp yerini native paywall ekranının alması gerekir.

**Durum:** Tasarım gereği (IAP henüz implement edilmedi). İzlemek gerekir.

---

### 2.2 `/gizlilik-politikasi` URL'sinde `.html` eksik

`profile_screen.dart:2174` linki `.html` uzantısı olmadan kullanıyor; diğer tüm
statik sayfalar `.html` ile açılıyor. nginx `try_files $uri $uri.html` fallback
sayesinde çalışıyor. Fonksiyonel sorun yok, minor tutarsızlık.

---

### 2.3 Share linkleri — 2026-10-19 öncesi 404

`/ilan/{id}`, `/profil/{username}`, `/yayin/{id}` path'leri nginx'te karşılıksız
kalıyordu (`try_files` sadece tam dosya adı aradığından HTML shell'e düşmüyordu).
`teqlif.com.conf`'a üç `location` bloğu eklenerek düzeltildi (`aa92d2ab`):

```nginx
location ~ ^/ilan(/|$)   { try_files /ilan.html   =404; }
location ~ ^/profil(/|$) { try_files /profil.html =404; }
location ~ ^/yayin(/|$)  { try_files /yayin.html  =404; }
```

---

### 2.4 OG meta tag'leri — bot'lar için boş

`ilan.html`, `profil.html`, `yayin.html` OG tag'lerini (`og:title`, `og:image` vb.)
JavaScript ile client-side set ediyor. WhatsApp / Telegram botları JS çalıştırmadığı
için link önizlemesi başlık/görsel olmadan açılıyor.

**Gerekli:** FastAPI'de `/ilan/{id}`, `/profil/{username}`, `/yayin/{id}` için
SSR endpoint — bot User-Agent tespiti + DB sorgusu + HTML template.

---

### 2.5 Web → Uygulama deep link yok

Kullanıcı telefon tarayıcısında `teqlif.com/ilan/123` açtığında uygulama açılmıyor,
web sayfası açılıyor. iOS Universal Links / Android App Links konfigürasyonu
(`apple-app-site-association`, `assetlinks.json`) implement edilmedi.

**Etki:** Paylaşım linkine tıklayan kullanıcı uygulamayı değil tarayıcıyı açar.

---

## 3. Share Servisi Özeti

`mobile/lib/services/share_service.dart` — dört giriş noktası:

| Kaynak | URL | Text | Görsel |
|--------|-----|------|--------|
| İlan detay | `teqlif.com/ilan/{id}` | `{title} — teqlif'te incele` | `_images.first` |
| Profil | `teqlif.com/profil/{username}` | `@{username} — teqlif'te incele` | `profile_image_url` |
| Canlı yayın | `teqlif.com/yayin/{streamId}` | `{title} — teqlif'te canlı izle` | `thumbnailUrl` |
| Davet (referral) | *(URL yok)* | ARB: `profileInviteShareText` + App Store linkleri | — |

**Not — Davet share:** `url` parametresi geçilmiyor → "Kopyala" seçeneği gösterilmiyor
(`widget.url.isNotEmpty` kontrolü). Kullanıcı metni kopyalamak için "Diğer" seçeneğini
kullanmak zorunda. Minor UX gap.

**Not — Instagram:** `shareToInstagramStory()` doğrudan Instagram Stories API
(`instagram-stories://`) değil, OS native share sheet açıyor (`Share.shareXFiles`).
"Story'ne görsel olarak ekle" etiketi ile beklenti uyuşmazlığı var.
