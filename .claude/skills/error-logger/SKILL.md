---
name: error-logger
description: Backend (FastAPI), Frontend (Vanilla JS) ve Mobil (Flutter) kodlarında hata yakalama (try-catch/except) ve loglama (Sentry/Loki) standartlarını uygular. Kod yazarken veya refactor ederken bu standartlara uymak için otomatik tetiklenir.
---
# Teqlif Hata Yönetimi ve Loglama Standartları

Görev: Bu projede yeni kod yazarken, mevcut kodu güncellerken veya hata ayıklarken KESİNLİKLE aşağıdaki hata yakalama ve loglama standartlarına uymalısın.

## 1. Backend Tarafı (FastAPI / Python)
- Merkezi loglama altyapımız Loki/Grafana tarafından izlenmektedir (`error.log`).
- Veritabanı işlemleri (SQLAlchemy), dosya okuma/yazma ve dış API çağrılarında mutlaka `try-except` bloğu kullan.
- Yakalanan hataları standart loglayıcı ile kaydet: `logger.error("İşlem sırasında hata: %s", str(e), exc_info=True)`
- Kullanıcıya dönülecek hatalarda HTTPException fırlatırken mantıklı status kodları (400, 404, 500) kullan.
- Kritik operasyonlarda (örn: ödeme, canlı yayın başlatma) oluşan hataları Sentry'e iletmek için `sentry_sdk.capture_exception(e)` metodunu kullanmayı unutma.

## 2. Mobil Tarafı (Flutter / Dart)
- Tüm asenkron ağ istekleri (API calls) ve veritabanı işlemlerini `try-catch` blokları ile sar.
- Yakalanan hataları Sentry'e detaylı ilet: `await Sentry.captureException(e, stackTrace: stackTrace);`
- Hata durumunda kullanıcı deneyimini bozmamak için projenin mevcut Snackbar veya Dialog yapılarını kullanarak kullanıcıya anlaşılır mesajlar göster. Konsola (debugPrint) sadece developer için log bas.

## 3. Web Frontend Tarafı (Vanilla JS)
- `async/await` içeren tüm fonksiyonlarda `try...catch` kullan.
- Hataları konsola basarken anlamlı etiketler kullan: `console.error("[Modül Adı] İşlem başarısız:", error);`
- Eğer işlem kritikse (Kayıt, giriş, teklif verme), hatayı Sentry JS SDK'sına gönder: `if (window.Sentry) { Sentry.captureException(error); }`
- Asla basit `alert()` kullanma; hataları UI üzerinde (DOM manipülasyonu ile uygun bir toast veya error-box içinde) göster.

## 🛑 Kesin Kurallar
- İçerisi boş olan (Silent) `catch` veya `except` blokları YAZMAK KESİNLİKLE YASAKTIR.
- Hatayı yutma; ya logla, ya Sentry'e yolla, ya da UI'da göster.