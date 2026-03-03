# Teqlif Platformu

Teqlif, kullanıcıların hem **Açık Arttırma (Müzayede)** usulüyle hem de **Sabit Fiyatlı** olarak ürünlerini listeleyebildiği ve teqlif verip/satın alabildiği yeni nesil bir e-ticaret platformudur. Proje, modern web teknolojileri (Next.js) ve çapraz platform mobil uygulama (Flutter) altyapısını bir arada sunar.

## 🚀 Temel Özellikler

- **Çoklu İlan Modelleri:**
  - **Açık Arttırma:** Satıcılar ürünlerine başlangıç fiyatı (`startingBid`) ve minimum artış miktarı / teqlif aralığı (`minBidStep`) belirleyebilirler. Alıcılar bu kurallara göre teqlif verir.
  - **Sabit Fiyat (Fixed Price):** Teklif mekanizmasının kapalı olduğu, satıcının belirlediği net fiyattan listelenen ve doğrudan iletişime geçilerek satılan ürün modeli.
- **Gelişmiş Teklif Yönetimi:** Satıcılar, ilanlarına gelen teklifleri görebilir, kabul edebilir (`ACCEPTED`) veya reddedebilir (`REJECTED`). Teklif kabul edildiğinde kazanan dışındaki rezerve teklifler iptal edilir.
- **Gerçek Zamanlıya Yakın Mesajlaşma:**
  - Satıcılar ve alıcılar arasında sipariş/teklif üzerine anında mesajlaşma.
  - Web uygulamasında her sayfadan erişilebilen *Global Chat Widget* ve özel *Dashboard Mesajlar* paneli.
- **Bildirimler:** Teklif aldığınızda, teklifiniz kabul edildiğinde veya yeni bir mesaj geldiğinde bildirim zili aracılığıyla haberdar olursunuz.
- **Mobil Entegrasyon:** iOS ve Android cihazlar için geliştirilmiş, API ile tam uyumlu çalışan, Riverpod durum yönetimli Flutter (Mobile) istemci. (FCM Push Notifications destekli).

## 🛠 Teknoloji Yığını (Tech Stack)

### Backend & Web Frontend
- **Framework:** Next.js 14/15 (App Router)
- **Dil:** TypeScript, React
- **Veritabanı & ORM:** PostgreSQL & Prisma ORM (`prisma/schema.prisma`)
- **Kimlik Doğrulama:** NextAuth.js (v5)
- **Stil & UI:** Tailwind CSS, Radix UI v.b.

### Mobil Uygulama (Flutter)
- **Framework:** Flutter (Android & iOS)
- **State Management:** Riverpod 2 (`flutter_riverpod`)
- **Ağ/HTTP:** Dio (`dio`)
- **Navigasyon:** GoRouter (`go_router`)
- **Yerel Depolama:** Flutter Secure Storage (JWT için)

## 📂 Proje Yapısı

```
teqlif/
├── app/                  # Next.js App Router sayfaları ve API uç noktaları (/api)
│   ├── api/              # Mobil ve Web uygulamasının tükettiği RESTful endpointler
│   ├── ad/               # İlan detayı sayfaları
│   ├── dashboard/        # Kullanıcı paneli (İlanlarım, Tekliflerim, Mesajlarım)
│   ├── post-ad/          # İlan ekleme sayfası
│   └── edit-ad/          # İlan düzenleme sayfası
├── components/           # React ortak bileşenleri (Navbar, Footer, Chat v.b.)
├── lib/                  # Yardımcı fonksiyonlar (Prisma client, rate-limit, utils)
├── mobile/               # Teqlif Flutter mobil proje dizini
│   ├── lib/
│   │   ├── config/       # Mobil router ve tema
│   │   ├── core/         # API istemcileri (dio) ve Veri Modelleri
│   │   ├── features/     # Ekranlar (Auth, Home, Ad, Dashboard, Messages)
│   │   └── widgets/      # Ortak mobil arayüz elemanları (örn: MainShell)
└── prisma/               # Veritabanı şeması ve migration dosyaları
```

## 💻 Kurulum ve Geliştirme

### Web (Next.js) Ortamını Başlatmak
1. Bağımlılıkları yükleyin: `npm install`
2. `.env` dosyanızı oluşturup veritabanı url'nizi girin (`DATABASE_URL=...`)
3. Veritabanını eşitleyin: `npx prisma db push`
4. Geliştirme sunucusunu çalıştırın: `npm run dev`

### Mobil (Flutter) Ortamını Başlatmak
1. `cd mobile` klasörüne girin.
2. `flutter pub get` ile bağımlılıkları yükleyin.
3. Geliştirme API url adresinizi `mobile/lib/core/api/endpoints.dart` içindeki `kBaseUrl` değişkenine ayarlayın. (Yerel ağda test için makinenizin yerel IP'sini girin).
4. `flutter run -d <cihaz_id>` komutu ile emülatör veya gerçek (iPhone/Android) cihazda başlatın.
