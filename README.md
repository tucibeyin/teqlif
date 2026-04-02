<div align="center">

<img src="https://img.shields.io/badge/-%E2%9A%A1%20Teqlif-06B6D4?style=for-the-badge&labelColor=0F172A&color=06B6D4" height="48" alt="Teqlif"/>

### Canlı yayın destekli · Gerçek zamanlı açık artırma · İlan platformu

<br/>

[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-asyncpg-336791?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![Redis](https://img.shields.io/badge/Redis-Pub%2FSub-DC382D?style=flat-square&logo=redis&logoColor=white)](https://redis.io)
[![LiveKit](https://img.shields.io/badge/LiveKit-WebRTC-00A0E3?style=flat-square)](https://livekit.io)
[![Firebase](https://img.shields.io/badge/Firebase-FCM-FFCA28?style=flat-square&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Sentry](https://img.shields.io/badge/Sentry-Monitored-362D59?style=flat-square&logo=sentry&logoColor=white)](https://sentry.io)
[![License](https://img.shields.io/badge/License-Private-red?style=flat-square)](.)

<br/>

**[📱 Mobil Mimari](#-mobil-uygulama-mimarisi) · [🏗 Sistem Mimarisi](#️-sistem-mimarisi) · [🗄 Veritabanı](#-veritabanı-şeması) · [🔒 Güvenlik](#-güvenlik-katmanları) · [⚙️ Kurulum](#️-kurulum)**

</div>

---

## 🎯 Teqlif Nedir?

**Teqlif**, alışverişi canlı yayın deneyimiyle birleştiren Türkiye odaklı çok platformlu bir **C2C ticaret uygulamasıdır.** Kullanıcılar ilan açar, doğrudan satın alabilir ya da gerçek zamanlı açık artırmayla rekabetçi teklifler verebilir. Satıcılar canlı yayınları sırasında ürünlerini tanıtıp anlık açık artırma başlatabilir.

| | Özellik | Açıklama |
|---|---|---|
| 📢 | **İlan Yönetimi** | Kategori/şehir bazlı ilan, görsel yükleme, doğrudan teklif alma |
| 🔴 | **Canlı Yayın** | WebRTC/LiveKit ile host + izleyici full-duplex |
| 🔨 | **Gerçek Zamanlı Açık Artırma** | WebSocket üzerinden anlık teklif, sayaç, kazanan bildirimi |
| 💬 | **Canlı Sohbet** | Yayın içi moderasyonlu mesajlaşma |
| 👥 | **Sosyal Katman** | Takip, hikaye (story), beğeni, değerlendirme, engelleme |
| 🛡 | **Moderasyon** | Co-host atama, susturma, yayından atma |
| 🔔 | **Push Bildirim** | Firebase FCM anlık bildirimler |
| 🌐 | **Web Arayüzü** | Vanilla JS hafif, SEO-uyumlu web paneli |

---

## 🏗️ Sistem Mimarisi

```mermaid
graph TB
    subgraph CLIENTS["📱 Client Katmanı"]
        MOB["Flutter Mobile<br/>iOS + Android"]
        WEB["Vanilla JS / HTML<br/>Web Arayüzü"]
    end

    subgraph EDGE["🔀 Edge"]
        NGINX["Nginx<br/>Reverse Proxy · SSL · Static"]
    end

    subgraph BACKEND["⚙️ Backend Katmanı"]
        API["FastAPI<br/>Uvicorn Async"]
        WORKER["ARQ Worker<br/>Async Job Queue"]
    end

    subgraph REALTIME["⚡ Gerçek Zamanlı"]
        WS["WebSocket Manager<br/>pubsub_listener · chat_listener"]
        LK["LiveKit Server<br/>WebRTC SFU"]
    end

    subgraph DATA["🗄 Veri Katmanı"]
        PG["PostgreSQL<br/>asyncpg · 20 Tablo"]
        RD["Redis<br/>Pub/Sub · Cache · Rate Limit"]
    end

    subgraph EXTERNAL["☁️ Dış Servisler"]
        FB["Firebase<br/>FCM Push"]
        ST["Sentry<br/>Error Tracking"]
        CF["Cloudflare<br/>Turnstile CAPTCHA"]
    end

    MOB -->|HTTPS / WSS| NGINX
    WEB -->|HTTPS / WSS| NGINX
    NGINX --> API
    API --> WS
    API <--> PG
    API <--> RD
    RD --> WS
    WS -->|broadcast| MOB
    WS -->|broadcast| WEB
    API --> LK
    MOB <-->|WebRTC| LK
    WEB <-->|WebRTC| LK
    WORKER --> FB
    WORKER <--> RD
    API --> WORKER
    API --> ST
    API --> CF

    style CLIENTS fill:#0F172A,stroke:#06B6D4,color:#F1F5F9
    style EDGE fill:#1E293B,stroke:#475569,color:#F1F5F9
    style BACKEND fill:#0F172A,stroke:#06B6D4,color:#F1F5F9
    style REALTIME fill:#1E293B,stroke:#06B6D4,color:#F1F5F9
    style DATA fill:#0F172A,stroke:#475569,color:#F1F5F9
    style EXTERNAL fill:#1E293B,stroke:#475569,color:#F1F5F9
```

---

## 📊 Veri Akışı Diyagramları

<details>
<summary><strong>🔨 Gerçek Zamanlı Açık Artırma — Teklif Akışı</strong></summary>

```mermaid
sequenceDiagram
    actor Kullanıcı
    participant API as FastAPI Router
    participant RL as Rate Limiter<br/>(slowapi)
    participant AUTH as JWT Auth
    participant REDIS as Redis<br/>(Lua Script)
    participant PG as PostgreSQL
    participant PS as Pub/Sub
    participant WS as WebSocket<br/>Manager
    participant Others as Diğer İstemciler

    Kullanıcı->>API: POST /api/auction/{id}/bid
    API->>RL: Rate limit kontrolü (2/s)
    alt Limit aşıldı
        RL-->>Kullanıcı: 429 Too Many Requests
    end
    RL->>AUTH: JWT doğrula
    alt Geçersiz token
        AUTH-->>Kullanıcı: 401 Unauthorized
    end
    AUTH->>REDIS: Atomik Lua Script<br/>(açık artırma aktif? teklif > mevcut?)
    alt Geçersiz teklif
        REDIS-->>Kullanıcı: 400 Bad Request
    end
    REDIS->>PG: Bid kaydı yaz
    PG-->>REDIS: OK
    REDIS->>PS: PUBLISH auction_broadcast
    PS->>WS: pubsub_listener tetiklendi
    WS->>Kullanıcı: ✅ Yeni teklif (kendi ekranı)
    WS->>Others: 🔔 Yeni teklif (tüm izleyiciler)
```

</details>

<details>
<summary><strong>🔴 Canlı Yayın Bağlantı Akışı</strong></summary>

```mermaid
sequenceDiagram
    actor Host
    actor Viewer
    participant API as FastAPI
    participant LK as LiveKit Server
    participant WS as WebSocket

    Host->>API: POST /api/streams (yayın başlat)
    API->>LK: Room oluştur + Host token
    LK-->>API: room_id + token
    API-->>Host: JoinTokenOut
    Host->>LK: room.connect(token)
    Host->>LK: Video/Audio publish
    Note over LK: Room aktif

    Viewer->>API: POST /api/streams/{id}/join
    API->>LK: Viewer token al
    LK-->>API: token
    API-->>Viewer: JoinTokenOut
    Viewer->>LK: room.connect(token)
    LK->>Viewer: TrackSubscribedEvent 🎥
    Viewer->>WS: WebSocket /ws/stream/{id}
    WS-->>Viewer: viewer_count, chat, auction events
```

</details>

<details>
<summary><strong>💬 WebSocket Mesaj Dağıtım Mimarisi</strong></summary>

```mermaid
graph LR
    subgraph SOURCES["Kaynak Eventler"]
        BID["Yeni Teklif"]
        CHAT["Yeni Mesaj"]
        MOD["Moderasyon\n(kick/mute)"]
        LIKE["Beğeni"]
        CNT["Viewer Count"]
    end

    subgraph REDIS["Redis Pub/Sub"]
        AB["auction_broadcast"]
        CB["chat_broadcast"]
    end

    subgraph MAIN["main.py — Async Tasks"]
        PL["pubsub_listener"]
        CL["chat_pubsub_listener"]
        HB["heartbeat_checker"]
    end

    subgraph CLIENTS["Bağlı İstemciler"]
        M1["📱 Mobil #1"]
        M2["📱 Mobil #2"]
        W1["🌐 Web #1"]
    end

    BID --> AB
    LIKE --> AB
    CNT --> AB
    CHAT --> CB
    MOD --> CB
    AB --> PL
    CB --> CL
    PL --> M1
    PL --> M2
    PL --> W1
    CL --> M1
    CL --> M2
    CL --> W1
```

</details>

<details>
<summary><strong>🔔 Push Bildirim Akışı</strong></summary>

```mermaid
flowchart LR
    E["Tetikleyici Event\n(Yeni teklif / Takipçi / Yayın)"]
    --> API["FastAPI Router"]
    --> ARQ["ARQ Worker Queue"]
    --> FB["Firebase Admin SDK"]
    FB --> IOS["FCM → APNs → 📱 iOS"]
    FB --> AND["FCM → 📱 Android"]
```

</details>

---

## 🗄 Veritabanı Şeması

```mermaid
erDiagram
    users {
        int id PK
        string username UK
        string email UK
        string hashed_password
        string avatar_url
        bool is_verified
        bool is_admin
        datetime created_at
    }

    listings {
        int id PK
        int user_id FK
        int category_id FK
        int city_id FK
        string title
        text description
        decimal price
        string status
        string thumbnail_url
        bool is_live
        datetime created_at
    }

    auctions {
        int id PK
        int listing_id FK
        decimal starting_price
        decimal current_price
        int current_winner_id FK
        datetime start_time
        datetime end_time
        string status
    }

    bids {
        int id PK
        int auction_id FK
        int user_id FK
        decimal amount
        datetime created_at
    }

    streams {
        int id PK
        int host_id FK
        string title
        string livekit_room_id
        string status
        string thumbnail_url
        int viewer_count
        datetime created_at
    }

    stories {
        int id PK
        int user_id FK
        string media_url
        string media_type
        int stream_id FK
        datetime expires_at
        int view_count
    }

    messages {
        int id PK
        int sender_id FK
        int receiver_id FK
        text content
        bool is_read
        datetime sent_at
    }

    notifications {
        int id PK
        int user_id FK
        string type
        json payload
        bool is_read
        datetime created_at
    }

    follows {
        int id PK
        int follower_id FK
        int following_id FK
        datetime created_at
    }

    favorites {
        int id PK
        int user_id FK
        int listing_id FK
        datetime created_at
    }

    ratings {
        int id PK
        int rater_id FK
        int rated_id FK
        int score
        string comment
        datetime created_at
    }

    listing_offers {
        int id PK
        int listing_id FK
        int user_id FK
        decimal amount
        string status
    }

    purchases {
        int id PK
        int buyer_id FK
        int listing_id FK
        decimal amount
        string status
        datetime created_at
    }

    reports {
        int id PK
        int reporter_id FK
        string target_type
        int target_id
        string reason
    }

    blocks {
        int id PK
        int blocker_id FK
        int blocked_id FK
    }

    analytics {
        int id PK
        int user_id FK
        string event_type
        json metadata
        datetime created_at
    }

    users ||--o{ listings : "oluşturur"
    users ||--o{ streams : "yayınlar"
    users ||--o{ bids : "teklif verir"
    users ||--o{ stories : "paylaşır"
    users ||--o{ messages : "gönderir"
    users ||--o{ follows : "takip eder"
    users ||--o{ favorites : "favoriler"
    users ||--o{ ratings : "değerlendirir"
    users ||--o{ purchases : "satın alır"
    listings ||--o| auctions : "barındırır"
    auctions ||--o{ bids : "alır"
    listings ||--o{ listing_offers : "alır"
    listings ||--o{ favorites : "favorilenir"
```

---

## 📱 Mobil Uygulama Mimarisi

<details>
<summary><strong>Navigasyon Haritası</strong></summary>

```mermaid
flowchart TD
    SPLASH["SplashScreen\n(JWT kontrol)"]

    SPLASH -->|Oturum var| MAIN
    SPLASH -->|Oturum yok| LOGIN

    subgraph AUTH["🔐 Auth Flow"]
        LOGIN["LoginScreen"] --> REG["RegisterScreen"]
        LOGIN --> GOOGLE["Google OAuth"]
    end

    AUTH --> MAIN

    subgraph MAIN["🏠 MainScreen — BottomNav"]
        HOME["Tab 0\nHomeScreen\n(İlanlar + Hikayeler)"]
        SEARCH["Tab 1\nSearchScreen"]
        NEW["Tab 2\nCreateListingScreen"]
        LIVE["Tab 3\nLiveListScreen"]
        PROFILE["Tab 4\nProfileScreen"]
    end

    HOME --> DETAIL["ListingDetailScreen\n+ AuctionPanel (WS)"]
    HOME --> STORY["StoryViewerScreen"]
    SEARCH --> SWIPE["SwipeLiveScreen\n(TikTok PageView)"]
    LIVE --> SWIPE
    PROFILE --> EDIT["Profil Düzenleme"]
    PROFILE --> HOST["HostStreamScreen\n(Kamera + Mikrofon)"]
    DETAIL --> PUBLIC["PublicProfileScreen"]
    PUBLIC --> VIEWER["ViewerStreamScreen\n(Tek Yayın)"]
    STORY --> VIEWER
```

</details>

<details>
<summary><strong>Canlı Yayın Ekranları — UX Farkları</strong></summary>

```mermaid
graph LR
    subgraph SWIPE["SwipeLiveScreen\n(TikTok UX)"]
        S1["List·StreamOut alır"]
        S2["PageView dikey scroll"]
        S3["Lazy token fetch\nher sayfa değişiminde"]
        S4["isActive lifecycle\nactivate / deactivate"]
        S5["Yayın sonu → Overlay\nsonraki yayına geç"]
    end

    subgraph VIEWER["ViewerStreamScreen\n(Tekli UX)"]
        V1["JoinTokenOut alır\n(hazır token)"]
        V2["Tek tam sayfa"]
        V3["mount → connect\nbir kez"]
        V4["LiveVideoPlayer widget"]
        V5["Yayın sonu → AlertDialog\nhome'a gitme"]
    end

    subgraph CALLERS["Çağrı Noktaları"]
        LS["live_list_screen.dart"]
        SS["search_screen.dart"]
        PP["public_profile_screen.dart"]
        SV["story_viewer_screen.dart"]
    end

    LS --> SWIPE
    SS --> SWIPE
    PP --> VIEWER
    SV --> VIEWER
```

</details>

<details>
<summary><strong>Flutter Klasör Yapısı</strong></summary>

```
mobile/lib/
│
├── 📄 main.dart                    # App entry, Riverpod, Firebase init
│
├── 📁 config/
│   ├── api.dart                    # Base URL, endpoint sabitleri
│   └── theme.dart                  # kPrimary (#06B6D4), dark/light tokens
│
├── 📁 models/                      # JSON → Dart (17 model)
│   ├── stream.dart                 # StreamOut, JoinTokenOut
│   ├── listing.dart                # ListingOut, ListingOffer
│   ├── auction.dart                # AuctionOut, BidOut
│   └── user.dart, story.dart ...
│
├── 📁 services/                    # API çağrıları + iş mantığı (17 servis)
│   ├── auth_service.dart           # JWT, login, register, refresh
│   ├── stream_service.dart         # Yayın CRUD + join/leave/like
│   ├── auction_service.dart        # Teklif endpoint'leri
│   ├── story_service.dart          # Hikaye yükle/izle/sil
│   ├── ws_service.dart             # WebSocket bağlantı yöneticisi
│   ├── storage_service.dart        # SharedPreferences (token, user)
│   └── push_notification_service.dart
│
├── 📁 providers/                   # Riverpod state provider'ları
│
├── 📁 screens/
│   ├── main_screen.dart            # BottomNav
│   ├── home_screen.dart            # Ana akış
│   ├── listing_detail_screen.dart  # İlan detayı + teklif formu
│   ├── search_screen.dart          # Arama + SwipeLiveScreen
│   ├── profile_screen.dart         # Kendi profil
│   ├── public_profile_screen.dart  # Başka profil + Yayın izle
│   ├── messages_screen.dart        # DM konuşmaları
│   ├── live/
│   │   ├── host_stream_screen.dart      # Yayıncı ekranı
│   │   ├── viewer_stream_screen.dart    # Tekli izleme
│   │   ├── swipe_live_screen.dart       # TikTok-stili PageView
│   │   └── live_list_screen.dart        # Aktif yayınlar listesi
│   └── story/
│       └── story_viewer_screen.dart
│
└── 📁 widgets/
    ├── auction_panel.dart           # Teklif girişi + aktif artırma UI
    ├── chat_panel.dart              # Gerçek zamanlı sohbet (WS)
    ├── global_keyboard_accessory.dart
    └── live/
        ├── floating_hearts.dart     # Uçuşan kalpler animasyonu
        ├── live_video_player.dart   # Video render wrapper
        └── viewer_top_bar.dart      # CANLI etiketi + izleyici sayacı
```

</details>

---

## 🛠 Teknoloji Yığını

<details>
<summary><strong>Backend (Python)</strong></summary>

| Katman | Paket | Versiyon | Kullanım |
|---|---|---|---|
| **Framework** | FastAPI | 0.115.0 | Async REST API + WebSocket |
| **Server** | Uvicorn (standard) | 0.30.6 | ASGI runtime |
| **ORM** | SQLAlchemy (asyncio) | 2.0.35 | Async DB operasyonları |
| **DB Driver** | asyncpg | 0.30.0 | PostgreSQL async sürücüsü |
| **Migration** | Alembic | 1.13.3 | Şema versiyonlama |
| **Cache** | fastapi-cache2 (Redis) | 0.2.2 | Endpoint önbellekleme |
| **Pub/Sub** | redis | 5.1.1 | Gerçek zamanlı mesaj dağıtımı |
| **Job Queue** | ARQ | 0.25.0 | Async iş kuyruğu |
| **Auth** | python-jose + passlib | 3.3.0 / 1.7.4 | JWT + Bcrypt |
| **Media** | livekit-api | 0.8.2 | Canlı yayın token yönetimi |
| **Push** | firebase-admin | 6.5.0 | FCM bildirimleri |
| **Monitoring** | sentry-sdk[fastapi] | 2.0.0 | Hata izleme |
| **Rate Limit** | slowapi | 0.1.9 | Endpoint bazlı limit |
| **XSS Koruma** | bleach | 6.1.0 | Input sanitizasyonu |
| **Captcha** | itsdangerous + CF | 2.2.0 | Turnstile doğrulama |
| **Content Filter** | better-profanity | 0.7.0 | Küfür filtreleme |
| **Template** | Jinja2 | 3.1.4 | Admin panel |
| **Image** | Pillow | 10.4.0 | Görsel işleme |

</details>

<details>
<summary><strong>Mobil (Flutter / Dart)</strong></summary>

| Paket | Versiyon | Kullanım |
|---|---|---|
| `livekit_client` | ^2.3.0 | WebRTC canlı yayın |
| `web_socket_channel` | ^3.0.0 | Gerçek zamanlı WebSocket |
| `flutter_riverpod` | ^2.4.9 | State yönetimi |
| `firebase_messaging` | ^16.1.2 | Push notification |
| `local_auth` | ^2.3.0 | Biyometrik giriş |
| `sentry_flutter` | ^9.14.0 | Mobil hata izleme |
| `cached_network_image` | ^3.3.1 | Görsel önbellekleme |
| `image_picker` | ^1.1.0 | Kamera / Galeri |
| `video_compress` | ^3.1.3 | Yükleme öncesi sıkıştırma |
| `connectivity_plus` | ^6.1.4 | Ağ durumu takibi |
| `cloudflare_turnstile` | ^1.2.0 | Captcha entegrasyonu |
| `shimmer` | ^3.0.0 | Yükleme iskelet efekti |
| `wakelock_plus` | ^1.2.10 | Yayın sırasında ekran aktif |
| `intl` | ^0.20.0 | i18n / Lokalizasyon |
| `app_badge_plus` | ^1.1.0 | Uygulama rozeti |
| `url_launcher` | ^6.3.0 | Dış link açma |

</details>

<details>
<summary><strong>Altyapı</strong></summary>

| Bileşen | Teknoloji | Rol |
|---|---|---|
| **Web Sunucu** | Nginx | Reverse proxy, SSL termination, static dosya servisi |
| **Süreç Yöneticisi** | Systemd | `teqlif-backend.service`, `teqlif-worker.service` |
| **Veritabanı** | PostgreSQL 14+ | Ana kalıcı depolama (20 tablo) |
| **Önbellek** | Redis 7+ | Pub/Sub, rate limit counter, session cache |
| **Medya Sunucusu** | LiveKit Cloud | WebRTC SFU — video/audio track yönetimi |
| **Push** | Firebase FCM | iOS (APNs üzerinden) + Android bildirim |
| **Hata Takibi** | Sentry | Backend + Flutter çift taraflı izleme |
| **Bot Koruması** | Cloudflare Turnstile | Kayıt / giriş captcha |
| **Dağıtım** | Fastlane | Android build + deploy otomasyonu |

</details>

---

## 🌐 API Haritası

<details>
<summary><strong>Tüm endpointleri göster (50+)</strong></summary>

### 🔐 Auth
| Method | Endpoint | Açıklama |
|---|---|---|
| `POST` | `/api/auth/register` | Kayıt (Turnstile captcha zorunlu) |
| `POST` | `/api/auth/login` | JWT token al |
| `POST` | `/api/auth/refresh` | Token yenile |
| `POST` | `/api/auth/logout` | Çıkış |
| `POST` | `/api/auth/google` | Google OAuth |
| `GET` | `/api/auth/me` | Oturum bilgisi |

### 📢 İlanlar
| Method | Endpoint | Açıklama |
|---|---|---|
| `GET` | `/api/listings` | İlan listesi (filtreli, sayfalama) |
| `POST` | `/api/listings` | İlan oluştur |
| `GET` | `/api/listings/{id}` | İlan detayı |
| `PUT` | `/api/listings/{id}` | İlan güncelle |
| `DELETE` | `/api/listings/{id}` | İlan sil |
| `POST` | `/api/listings/{id}/offer` | Fiyat teklifi gönder |
| `GET` | `/api/listings/{id}/offers` | Gelen teklifler |

### 🔨 Açık Artırma
| Method | Endpoint | Açıklama |
|---|---|---|
| `GET` | `/api/auction/{id}` | Aktif açık artırma bilgisi |
| `POST` | `/api/auction/{id}/bid` | **Teklif ver** (rate limited: 2/s) |
| `WS` | `/ws/auction/{stream_id}` | Canlı teklif akışı |

### 🔴 Yayın (Stream)
| Method | Endpoint | Açıklama |
|---|---|---|
| `GET` | `/api/streams` | Aktif yayınlar |
| `POST` | `/api/streams` | Yayın başlat |
| `GET` | `/api/streams/{id}` | Yayın detayı |
| `DELETE` | `/api/streams/{id}` | Yayını bitir |
| `POST` | `/api/streams/{id}/join` | İzleyici token al |
| `POST` | `/api/streams/{id}/leave` | Yayından ayrıl |
| `POST` | `/api/streams/{id}/like` | Beğen |
| `WS` | `/ws/stream/{id}` | Sohbet + izleyici sayısı |

### 👥 Sosyal
| Method | Endpoint | Açıklama |
|---|---|---|
| `GET` | `/api/users/{username}` | Kullanıcı profili |
| `POST` | `/api/follows/{username}` | Takip et |
| `DELETE` | `/api/follows/{username}` | Takibi bırak |
| `GET` | `/api/search` | Arama (ilan + kullanıcı) |
| `POST` | `/api/favorites/{id}` | Favoriye ekle |
| `GET` | `/api/favorites` | Favorilerim |
| `GET` | `/api/stories` | Takip edilen hikayeler |
| `POST` | `/api/stories` | Hikaye paylaş |
| `POST` | `/api/ratings/{username}` | Değerlendir |
| `POST` | `/api/reports` | Şikayet et |

### 💬 Mesajlaşma
| Method | Endpoint | Açıklama |
|---|---|---|
| `GET` | `/api/messages` | Konuşma listesi |
| `POST` | `/api/messages/{username}` | Mesaj gönder |
| `WS` | `/ws/messages` | Gerçek zamanlı mesaj |

### 🛡 Moderasyon
| Method | Endpoint | Açıklama |
|---|---|---|
| `POST` | `/api/moderation/{stream_id}/mute` | Sustur |
| `POST` | `/api/moderation/{stream_id}/unmute` | Susturmayı kaldır |
| `POST` | `/api/moderation/{stream_id}/kick` | Yayından at |
| `POST` | `/api/moderation/{stream_id}/promote` | Co-host ata |
| `POST` | `/api/moderation/{stream_id}/demote` | Co-host indir |

</details>

---

## 🔒 Güvenlik Katmanları

```mermaid
flowchart TD
    REQ(["İstek Geldi"])

    REQ --> L1
    L1{"1️⃣ Nginx\nRate Limiting\nlimit_req_zone"}
    L1 -->|Aşıldı| R1["❌ 429"]
    L1 -->|OK| L2

    L2{"2️⃣ SecurityMiddleware\nXSS · CORS · Header"}
    L2 -->|Şüpheli| R2["❌ 400"]
    L2 -->|OK| L3

    L3{"3️⃣ slowapi\nEndpoint Bazlı Limit\nRedis Counter"}
    L3 -->|Aşıldı| R3["❌ 429"]
    L3 -->|OK| L4

    L4{"4️⃣ JWT Doğrulama\npython-jose\nHMAC-SHA256"}
    L4 -->|Geçersiz| R4["❌ 401"]
    L4 -->|OK| L5

    L5{"5️⃣ Sanitizer\nbleach ile XSS\nTüm string girdiler"}
    L5 -->|OK| L6

    L6{"6️⃣ Yetkilendirme\nKaynak sahipliği\n(kendi ilanı?)"}
    L6 -->|Yetkisiz| R6["❌ 403"]
    L6 -->|OK| BIZ

    BIZ(["✅ İş Mantığı"])

    style REQ fill:#06B6D4,color:#0F172A
    style BIZ fill:#16A34A,color:#fff
    style R1 fill:#EF4444,color:#fff
    style R2 fill:#EF4444,color:#fff
    style R3 fill:#EF4444,color:#fff
    style R4 fill:#EF4444,color:#fff
    style R6 fill:#EF4444,color:#fff
```

> [!NOTE]
> Ek katmanlar: **Cloudflare Turnstile** (bot koruması) · **better-profanity** (içerik filtresi) · **Bcrypt** (şifre hash, cost:12) · **SSL/TLS** (Let's Encrypt via Nginx) · **Sentry** (güvenlik istisnaları dahil tüm exception izleme)

---

## 🚀 Deployment Mimarisi

```mermaid
graph TB
    subgraph VPS["🖥 VPS — Ubuntu"]
        NGINX["Nginx\n:80 → :443\nSSL · Static"]
        API["FastAPI\nSystemd :8000"]
        WORKER["ARQ Worker\nSystemd"]
        PG["PostgreSQL"]
        RD["Redis"]

        NGINX --> API
        API --> WORKER
        API <--> PG
        API <--> RD
        WORKER <--> RD
    end

    INTERNET(["🌐 İnternet"]) --> NGINX
    API <-->|"LiveKit API\n(token)"| LKC["☁️ LiveKit Cloud\nWebRTC SFU"]
    WORKER --> FCM["☁️ Firebase\nFCM"]
    API --> SENTRY["☁️ Sentry\nError Tracking"]
```

**Systemd Servisleri:**

| Servis | Açıklama |
|---|---|
| `teqlif-backend.service` | FastAPI (uvicorn async) |
| `teqlif-worker.service` | ARQ async job worker |
| `postgresql.service` | Veritabanı |
| `redis.service` | Cache + Pub/Sub |
| `nginx.service` | Ters proxy + SSL |

---

## ⚙️ Kurulum

> [!IMPORTANT]
> PostgreSQL 14+, Redis 7+ ve Python 3.11+ gereklidir.

<details>
<summary><strong>Backend Kurulumu</strong></summary>

```bash
cd teqlif/backend

# Virtual environment
python -m venv .venv && source .venv/bin/activate

# Bağımlılıklar
pip install -r requirements.txt

# Ortam değişkenleri
cp .env.example .env
# .env içinde: DATABASE_URL, REDIS_URL, LIVEKIT_*, JWT_SECRET, FIREBASE_*, SENTRY_DSN

# Migration
alembic upgrade head

# Backend başlat
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Worker başlat (ayrı terminal)
arq app.worker.WorkerSettings
```

</details>

<details>
<summary><strong>Mobil Kurulumu</strong></summary>

```bash
cd teqlif/mobile

# Bağımlılıklar
flutter pub get

# Lokalizasyon dosyalarını oluştur
flutter gen-l10n

# iOS
flutter run -d ios

# Android
flutter run -d android

# Release build (Android)
fastlane android build
```

</details>

<details>
<summary><strong>Veritabanı Komutları</strong></summary>

```bash
# Yeni migration oluştur (model değişikliği sonrası ZORUNLU)
alembic revision --autogenerate -m "aciklama"

# Migration uygula
alembic upgrade head

# Bir adım geri al
alembic downgrade -1

# Migration geçmişini gör
alembic history --verbose
```

> [!WARNING]
> Model dosyasındaki her değişiklikten sonra mutlaka `alembic revision --autogenerate` çalıştırın. Aksi hâlde canlı ortamda şema uyumsuzluğu oluşur.

</details>

---

## 📐 Geliştirici Kuralları

> [!TIP]
> Bu kurallar hem backend hem mobil için bağlayıcıdır. PR'larda bu kurallara aykırı değişiklikler kabul edilmez.

<details>
<summary><strong>Backend Kuralları</strong></summary>

- ✅ **Tam asenkronluk** — Tüm I/O `async/await` ile yazılmalıdır; `time.sleep()` yasaktır
- ✅ **Modüler router** — `main.py` şişirilmez; yeni domain → `/app/routers/` altına yeni dosya
- ✅ **Girdi sanitizasyonu** — `sanitizer.py` tüm kullanıcı girdilerine uygulanmalıdır
- ✅ **ENV yönetimi** — Gizli anahtarlar `config.py` (Pydantic Settings) üzerinden; hard-code yasaktır
- ✅ **Hata loglama** — Beklenmedik hatalar `sentry_sdk.capture_exception()` ile iletilmeli
- ✅ **Migration zorunluluğu** — Model değişikliği = Alembic migration; sıfır istisna

</details>

<details>
<summary><strong>Mobil Kuralları</strong></summary>

- ✅ **Servis katmanı** — Tüm API çağrıları `/services/*.dart` üzerinden; widget içinden HTTP yasaktır
- ✅ **Widget bölme** — 300 satırı geçen ekranlar alt widget'lara bölünür
- ✅ **Renk yönetimi** — `Theme.of(context)` veya `kPrimary` kullanılır; `Colors.white` hard-code yasaktır
- ✅ **Klavye** — Tüm form ekranlarında `global_keyboard_accessory.dart` veya `resizeToAvoidBottomInset` yapısına dikkat
- ✅ **Performans** — Liste güncellemelerinde `StreamBuilder` / localized state tercih edilir; tüm ekranı `setState` ile yeniden çizmekten kaçınılır

</details>

<details>
<summary><strong>Web Kuralları</strong></summary>

- ✅ **Framework yok** — React, Vue, Tailwind eklenmez; Vanilla JS + saf CSS
- ✅ **DOM performansı** — Tüm listeyi yeniden oluşturmak yerine sadece değişen element güncellenir
- ✅ **Mobile-first** — `grid` + `flexbox` + `media queries` ile responsive tasarım
- ✅ **WebSocket reconnect** — Bağlantı kesildiğinde otomatik yeniden bağlanma + kullanıcı uyarısı

</details>

---

## 🎨 Tasarım Sistemi

| Token | Renk | Hex | Kullanım |
|---|---|:---:|---|
| `kPrimary` | 🟦 Cyan-500 | `#06B6D4` | Ana buton, vurgu, aktif ikonlar |
| `Dark BG` | ⬛ Slate-900 | `#0F172A` | Sayfa arka planı |
| `Surface` | ⬛ Slate-800 | `#1E293B` | Kart, panel, bottom sheet |
| `Border` | ⬛ Slate-700 | `#334155` | Ayırıcı çizgiler |
| `Text Primary` | ⬜ Slate-100 | `#F1F5F9` | Ana metin |
| `Text Secondary` | 🔘 Slate-400 | `#94A3B8` | İkincil, açıklama metni |
| `Success` | 🟩 Green-600 | `#16A34A` | Başarı mesajı, moderatör atama |
| `Warning` | 🟧 Amber-600 | `#D97706` | Uyarı, susturma bildirimi |
| `Error` | 🟥 Red-500 | `#EF4444` | Hata, kick bildirimi |
| `Live` | 🟥 Red-500 | `#EF4444` | CANLI etiketi |
| `CoHost` | 🌊 Cyan-400 | `#22D3EE` | Co-host kullanıcı adı vurgusu |

---

<div align="center">

**⚡ Teqlif** — Canlı. Gerçek. Anlık.

*Made with ❤️ in Turkey*

</div>
