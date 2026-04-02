<div align="center">

<img src="https://img.shields.io/badge/-%E2%9A%A1%20Teqlif-06B6D4?style=for-the-badge&labelColor=0F172A&color=06B6D4" height="48" alt="Teqlif"/>

### Live-streaming · Real-time auctions · Marketplace platform

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

**[📱 Mobile Architecture](#-mobile-app-architecture) · [🏗 System Architecture](#️-system-architecture) · [🗄 Database](#-database-schema) · [🔒 Security](#-security-layers) · [⚙️ Setup](#️-setup)**

</div>

---

## 🎯 What is Teqlif?

**Teqlif** is a multi-platform **C2C marketplace** that merges social live-streaming with commerce, focused on the Turkish market. Users can list items, buy directly, or compete in real-time auctions. Sellers can showcase products during live broadcasts and launch instant auctions — turning shopping into entertainment.

| | Feature | Description |
|---|---|---|
| 📢 | **Listing Management** | Category/city-based listings, image upload, direct offer system |
| 🔴 | **Live Streaming** | Low-latency host + viewer streams via WebRTC / LiveKit |
| 🔨 | **Real-time Auctions** | Live bidding, countdown timer, winner notification over WebSocket |
| 💬 | **Live Chat** | Moderated real-time messaging within streams |
| 👥 | **Social Layer** | Follow, story, likes, ratings, blocking |
| 🛡 | **Moderation** | Co-host assignment, mute, kick |
| 🔔 | **Push Notifications** | Instant alerts via Firebase FCM |
| 🌐 | **Web Interface** | Lightweight, SEO-friendly Vanilla JS web panel |

---

## 🏗️ System Architecture

```mermaid
graph TB
    subgraph CLIENTS["📱 Client Layer"]
        MOB["Flutter Mobile<br/>iOS + Android"]
        WEB["Vanilla JS / HTML<br/>Web Interface"]
    end

    subgraph EDGE["🔀 Edge"]
        NGINX["Nginx<br/>Reverse Proxy · SSL · Static"]
    end

    subgraph BACKEND["⚙️ Backend Layer"]
        API["FastAPI<br/>Uvicorn Async"]
        WORKER["ARQ Worker<br/>Async Job Queue"]
    end

    subgraph REALTIME["⚡ Real-time"]
        WS["WebSocket Manager<br/>pubsub_listener · chat_listener"]
        LK["LiveKit Server<br/>WebRTC SFU"]
    end

    subgraph DATA["🗄 Data Layer"]
        PG["PostgreSQL<br/>asyncpg · 20 Tables"]
        RD["Redis<br/>Pub/Sub · Cache · Rate Limit"]
    end

    subgraph EXTERNAL["☁️ External Services"]
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

## 📊 Data Flow Diagrams

<details>
<summary><strong>🔨 Real-time Auction — Bid Flow</strong></summary>

```mermaid
sequenceDiagram
    actor User
    participant API as FastAPI Router
    participant RL as Rate Limiter<br/>(slowapi)
    participant AUTH as JWT Auth
    participant REDIS as Redis<br/>(Lua Script)
    participant PG as PostgreSQL
    participant PS as Pub/Sub
    participant WS as WebSocket<br/>Manager
    participant Others as Other Clients

    User->>API: POST /api/auction/{id}/bid
    API->>RL: Rate limit check (2/s)
    alt Limit exceeded
        RL-->>User: 429 Too Many Requests
    end
    RL->>AUTH: Validate JWT
    alt Invalid token
        AUTH-->>User: 401 Unauthorized
    end
    AUTH->>REDIS: Atomic Lua Script<br/>(auction active? bid > current?)
    alt Invalid bid
        REDIS-->>User: 400 Bad Request
    end
    REDIS->>PG: Write bid record
    PG-->>REDIS: OK
    REDIS->>PS: PUBLISH auction_broadcast
    PS->>WS: pubsub_listener triggered
    WS->>User: ✅ New bid (own screen)
    WS->>Others: 🔔 New bid (all viewers)
```

</details>

<details>
<summary><strong>🔴 Live Stream Connection Flow</strong></summary>

```mermaid
sequenceDiagram
    actor Host
    actor Viewer
    participant API as FastAPI
    participant LK as LiveKit Server
    participant WS as WebSocket

    Host->>API: POST /api/streams (start broadcast)
    API->>LK: Create room + Host token
    LK-->>API: room_id + token
    API-->>Host: JoinTokenOut
    Host->>LK: room.connect(token)
    Host->>LK: Publish Video/Audio
    Note over LK: Room is live

    Viewer->>API: POST /api/streams/{id}/join
    API->>LK: Get viewer token
    LK-->>API: token
    API-->>Viewer: JoinTokenOut
    Viewer->>LK: room.connect(token)
    LK->>Viewer: TrackSubscribedEvent 🎥
    Viewer->>WS: WebSocket /ws/stream/{id}
    WS-->>Viewer: viewer_count, chat, auction events
```

</details>

<details>
<summary><strong>💬 WebSocket Broadcast Architecture</strong></summary>

```mermaid
graph LR
    subgraph SOURCES["Source Events"]
        BID["New Bid"]
        CHAT["New Message"]
        MOD["Moderation\n(kick/mute)"]
        LIKE["Like"]
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

    subgraph CLIENTS["Connected Clients"]
        M1["📱 Mobile #1"]
        M2["📱 Mobile #2"]
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
<summary><strong>🔔 Push Notification Flow</strong></summary>

```mermaid
flowchart LR
    E["Trigger Event\n(New bid / New follower / Stream started)"]
    --> API["FastAPI Router"]
    --> ARQ["ARQ Worker Queue"]
    --> FB["Firebase Admin SDK"]
    FB --> IOS["FCM → APNs → 📱 iOS"]
    FB --> AND["FCM → 📱 Android"]
```

</details>

---

## 🗄 Database Schema

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

    users ||--o{ listings : "creates"
    users ||--o{ streams : "broadcasts"
    users ||--o{ bids : "places"
    users ||--o{ stories : "shares"
    users ||--o{ messages : "sends"
    users ||--o{ follows : "follows"
    users ||--o{ favorites : "saves"
    users ||--o{ ratings : "rates"
    users ||--o{ purchases : "buys"
    listings ||--o| auctions : "hosts"
    auctions ||--o{ bids : "receives"
    listings ||--o{ listing_offers : "receives"
    listings ||--o{ favorites : "saved by"
```

---

## 📱 Mobile App Architecture

<details>
<summary><strong>Navigation Map</strong></summary>

```mermaid
flowchart TD
    SPLASH["SplashScreen\n(JWT check)"]

    SPLASH -->|Session exists| MAIN
    SPLASH -->|No session| LOGIN

    subgraph AUTH["🔐 Auth Flow"]
        LOGIN["LoginScreen"] --> REG["RegisterScreen"]
        LOGIN --> GOOGLE["Google OAuth"]
    end

    AUTH --> MAIN

    subgraph MAIN["🏠 MainScreen — BottomNav"]
        HOME["Tab 0\nHomeScreen\n(Listings + Stories)"]
        SEARCH["Tab 1\nSearchScreen"]
        NEW["Tab 2\nCreateListingScreen"]
        LIVE["Tab 3\nLiveListScreen"]
        PROFILE["Tab 4\nProfileScreen"]
    end

    HOME --> DETAIL["ListingDetailScreen\n+ AuctionPanel (WS)"]
    HOME --> STORY["StoryViewerScreen"]
    SEARCH --> SWIPE["SwipeLiveScreen\n(TikTok-style PageView)"]
    LIVE --> SWIPE
    PROFILE --> EDIT["Edit Profile"]
    PROFILE --> HOST["HostStreamScreen\n(Camera + Microphone)"]
    DETAIL --> PUBLIC["PublicProfileScreen"]
    PUBLIC --> VIEWER["ViewerStreamScreen\n(Single stream)"]
    STORY --> VIEWER
```

</details>

<details>
<summary><strong>Live Stream Screens — UX Differences</strong></summary>

```mermaid
graph LR
    subgraph SWIPE["SwipeLiveScreen\n(TikTok UX)"]
        S1["Takes List·StreamOut"]
        S2["Vertical PageView scroll"]
        S3["Lazy token fetch\non each page change"]
        S4["isActive lifecycle\nactivate / deactivate"]
        S5["Stream ended → Overlay\nswipe to next stream"]
    end

    subgraph VIEWER["ViewerStreamScreen\n(Single UX)"]
        V1["Takes JoinTokenOut\n(pre-fetched token)"]
        V2["Single full-page"]
        V3["mount → connect\nonce only"]
        V4["LiveVideoPlayer widget"]
        V5["Stream ended → AlertDialog\nnavigate home"]
    end

    subgraph CALLERS["Call Sites"]
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
<summary><strong>Flutter Folder Structure</strong></summary>

```
mobile/lib/
│
├── 📄 main.dart                    # App entry, Riverpod, Firebase init
│
├── 📁 config/
│   ├── api.dart                    # Base URL, endpoint constants
│   └── theme.dart                  # kPrimary (#06B6D4), dark/light tokens
│
├── 📁 models/                      # JSON → Dart (17 models)
│   ├── stream.dart                 # StreamOut, JoinTokenOut
│   ├── listing.dart                # ListingOut, ListingOffer
│   ├── auction.dart                # AuctionOut, BidOut
│   └── user.dart, story.dart ...
│
├── 📁 services/                    # API calls + business logic (17 services)
│   ├── auth_service.dart           # JWT, login, register, refresh
│   ├── stream_service.dart         # Stream CRUD + join/leave/like
│   ├── auction_service.dart        # Bid endpoints
│   ├── story_service.dart          # Story upload/view/delete
│   ├── ws_service.dart             # WebSocket connection manager
│   ├── storage_service.dart        # SharedPreferences (token, user)
│   └── push_notification_service.dart
│
├── 📁 providers/                   # Riverpod state providers
│
├── 📁 screens/
│   ├── main_screen.dart            # BottomNav
│   ├── home_screen.dart            # Main feed
│   ├── listing_detail_screen.dart  # Listing detail + offer form
│   ├── search_screen.dart          # Search + SwipeLiveScreen
│   ├── profile_screen.dart         # Own profile
│   ├── public_profile_screen.dart  # Other user profile + watch stream
│   ├── messages_screen.dart        # DM conversations
│   ├── live/
│   │   ├── host_stream_screen.dart      # Broadcaster view
│   │   ├── viewer_stream_screen.dart    # Single-stream viewer
│   │   ├── swipe_live_screen.dart       # TikTok-style PageView
│   │   └── live_list_screen.dart        # Active streams list
│   └── story/
│       └── story_viewer_screen.dart
│
└── 📁 widgets/
    ├── auction_panel.dart           # Bid input + live auction UI
    ├── chat_panel.dart              # Real-time chat (WebSocket)
    ├── global_keyboard_accessory.dart
    └── live/
        ├── floating_hearts.dart     # Floating hearts animation
        ├── live_video_player.dart   # Video render wrapper
        └── viewer_top_bar.dart      # LIVE badge + viewer counter
```

</details>

---

## 🛠 Tech Stack

<details>
<summary><strong>Backend (Python)</strong></summary>

| Layer | Package | Version | Purpose |
|---|---|---|---|
| **Framework** | FastAPI | 0.115.0 | Async REST API + WebSocket |
| **Server** | Uvicorn (standard) | 0.30.6 | ASGI runtime |
| **ORM** | SQLAlchemy (asyncio) | 2.0.35 | Async database operations |
| **DB Driver** | asyncpg | 0.30.0 | PostgreSQL async driver |
| **Migration** | Alembic | 1.13.3 | Schema versioning |
| **Cache** | fastapi-cache2 (Redis) | 0.2.2 | Endpoint caching |
| **Pub/Sub** | redis | 5.1.1 | Real-time message broadcasting |
| **Job Queue** | ARQ | 0.25.0 | Async background jobs |
| **Auth** | python-jose + passlib | 3.3.0 / 1.7.4 | JWT + Bcrypt |
| **Media** | livekit-api | 0.8.2 | Live stream token management |
| **Push** | firebase-admin | 6.5.0 | FCM notifications |
| **Monitoring** | sentry-sdk[fastapi] | 2.0.0 | Error tracking |
| **Rate Limiting** | slowapi | 0.1.9 | Per-endpoint rate limits |
| **XSS Protection** | bleach | 6.1.0 | Input sanitization |
| **Captcha** | itsdangerous + CF | 2.2.0 | Turnstile validation |
| **Content Filter** | better-profanity | 0.7.0 | Profanity filtering |
| **Template** | Jinja2 | 3.1.4 | Admin panel templates |
| **Image** | Pillow | 10.4.0 | Image processing |

</details>

<details>
<summary><strong>Mobile (Flutter / Dart)</strong></summary>

| Package | Version | Purpose |
|---|---|---|
| `livekit_client` | ^2.3.0 | WebRTC live streaming |
| `web_socket_channel` | ^3.0.0 | Real-time WebSocket |
| `flutter_riverpod` | ^2.4.9 | State management |
| `firebase_messaging` | ^16.1.2 | Push notifications |
| `local_auth` | ^2.3.0 | Biometric login |
| `sentry_flutter` | ^9.14.0 | Mobile error tracking |
| `cached_network_image` | ^3.3.1 | Image caching |
| `image_picker` | ^1.1.0 | Camera / Gallery |
| `video_compress` | ^3.1.3 | Pre-upload compression |
| `connectivity_plus` | ^6.1.4 | Network status |
| `cloudflare_turnstile` | ^1.2.0 | CAPTCHA integration |
| `shimmer` | ^3.0.0 | Loading skeleton effect |
| `wakelock_plus` | ^1.2.10 | Keep screen on during stream |
| `intl` | ^0.20.0 | i18n / Localization |
| `app_badge_plus` | ^1.1.0 | App icon badge |
| `url_launcher` | ^6.3.0 | Open external links |

</details>

<details>
<summary><strong>Infrastructure</strong></summary>

| Component | Technology | Role |
|---|---|---|
| **Web Server** | Nginx | Reverse proxy, SSL termination, static file serving |
| **Process Manager** | Systemd | `teqlif-backend.service`, `teqlif-worker.service` |
| **Database** | PostgreSQL 14+ | Primary persistent storage (20 tables) |
| **Cache** | Redis 7+ | Pub/Sub, rate limit counters, session cache |
| **Media Server** | LiveKit Cloud | WebRTC SFU — video/audio track management |
| **Push** | Firebase FCM | iOS (via APNs) + Android notifications |
| **Error Tracking** | Sentry | Dual-side monitoring (backend + Flutter) |
| **Bot Protection** | Cloudflare Turnstile | Registration / login CAPTCHA |
| **Deployment** | Fastlane | Android build + deploy automation |

</details>

---

## 🌐 API Map

<details>
<summary><strong>View all endpoints (50+)</strong></summary>

### 🔐 Auth
| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/register` | Register (Turnstile CAPTCHA required) |
| `POST` | `/api/auth/login` | Get JWT token |
| `POST` | `/api/auth/refresh` | Refresh token |
| `POST` | `/api/auth/logout` | Log out |
| `POST` | `/api/auth/google` | Google OAuth |
| `GET` | `/api/auth/me` | Current session info |

### 📢 Listings
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/listings` | Listing feed (filterable, paginated) |
| `POST` | `/api/listings` | Create listing |
| `GET` | `/api/listings/{id}` | Listing detail |
| `PUT` | `/api/listings/{id}` | Update listing |
| `DELETE` | `/api/listings/{id}` | Delete listing |
| `POST` | `/api/listings/{id}/offer` | Submit price offer |
| `GET` | `/api/listings/{id}/offers` | Incoming offers |

### 🔨 Auctions
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/auction/{id}` | Active auction info |
| `POST` | `/api/auction/{id}/bid` | **Place bid** (rate limited: 2/s) |
| `WS` | `/ws/auction/{stream_id}` | Live bid stream |

### 🔴 Streams
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/streams` | Active streams |
| `POST` | `/api/streams` | Start a stream |
| `GET` | `/api/streams/{id}` | Stream detail |
| `DELETE` | `/api/streams/{id}` | End stream |
| `POST` | `/api/streams/{id}/join` | Get viewer token |
| `POST` | `/api/streams/{id}/leave` | Leave stream |
| `POST` | `/api/streams/{id}/like` | Like stream |
| `WS` | `/ws/stream/{id}` | Chat + viewer count |

### 👥 Social
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/users/{username}` | User profile |
| `POST` | `/api/follows/{username}` | Follow user |
| `DELETE` | `/api/follows/{username}` | Unfollow user |
| `GET` | `/api/search` | Search (listings + users) |
| `POST` | `/api/favorites/{id}` | Save to favorites |
| `GET` | `/api/favorites` | My favorites |
| `GET` | `/api/stories` | Stories from followed users |
| `POST` | `/api/stories` | Share a story |
| `POST` | `/api/ratings/{username}` | Rate a user |
| `POST` | `/api/reports` | Report content |

### 💬 Messaging
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/messages` | Conversation list |
| `POST` | `/api/messages/{username}` | Send message |
| `WS` | `/ws/messages` | Real-time messaging |

### 🛡 Moderation
| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/moderation/{stream_id}/mute` | Mute user |
| `POST` | `/api/moderation/{stream_id}/unmute` | Unmute user |
| `POST` | `/api/moderation/{stream_id}/kick` | Kick from stream |
| `POST` | `/api/moderation/{stream_id}/promote` | Assign co-host |
| `POST` | `/api/moderation/{stream_id}/demote` | Remove co-host |

</details>

---

## 🔒 Security Layers

```mermaid
flowchart TD
    REQ(["Request Received"])

    REQ --> L1
    L1{"1️⃣ Nginx\nRate Limiting\nlimit_req_zone"}
    L1 -->|Exceeded| R1["❌ 429"]
    L1 -->|OK| L2

    L2{"2️⃣ SecurityMiddleware\nXSS · CORS · Headers"}
    L2 -->|Suspicious| R2["❌ 400"]
    L2 -->|OK| L3

    L3{"3️⃣ slowapi\nPer-endpoint Limit\nRedis Counter"}
    L3 -->|Exceeded| R3["❌ 429"]
    L3 -->|OK| L4

    L4{"4️⃣ JWT Validation\npython-jose\nHMAC-SHA256"}
    L4 -->|Invalid| R4["❌ 401"]
    L4 -->|OK| L5

    L5{"5️⃣ Sanitizer\nbleach XSS cleanup\nAll string inputs"}
    L5 -->|OK| L6

    L6{"6️⃣ Authorization\nResource ownership\n(owns listing?)"}
    L6 -->|Forbidden| R6["❌ 403"]
    L6 -->|OK| BIZ

    BIZ(["✅ Business Logic"])

    style REQ fill:#06B6D4,color:#0F172A
    style BIZ fill:#16A34A,color:#fff
    style R1 fill:#EF4444,color:#fff
    style R2 fill:#EF4444,color:#fff
    style R3 fill:#EF4444,color:#fff
    style R4 fill:#EF4444,color:#fff
    style R6 fill:#EF4444,color:#fff
```

> [!NOTE]
> Additional layers: **Cloudflare Turnstile** (bot protection) · **better-profanity** (content filter) · **Bcrypt** (password hash, cost:12) · **SSL/TLS** (Let's Encrypt via Nginx) · **Sentry** (all exceptions including security events)

---

## 🚀 Deployment Architecture

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

    INTERNET(["🌐 Internet"]) --> NGINX
    API <-->|"LiveKit API\n(token)"| LKC["☁️ LiveKit Cloud\nWebRTC SFU"]
    WORKER --> FCM["☁️ Firebase\nFCM"]
    API --> SENTRY["☁️ Sentry\nError Tracking"]
```

**Systemd Services:**

| Service | Description |
|---|---|
| `teqlif-backend.service` | FastAPI (uvicorn async) |
| `teqlif-worker.service` | ARQ async job worker |
| `postgresql.service` | Database |
| `redis.service` | Cache + Pub/Sub |
| `nginx.service` | Reverse proxy + SSL |

---

## ⚙️ Setup

> [!IMPORTANT]
> PostgreSQL 14+, Redis 7+ and Python 3.11+ are required.

<details>
<summary><strong>Backend Setup</strong></summary>

```bash
cd teqlif/backend

# Virtual environment
python -m venv .venv && source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Fill in: DATABASE_URL, REDIS_URL, LIVEKIT_*, JWT_SECRET, FIREBASE_*, SENTRY_DSN

# Run migrations
alembic upgrade head

# Start backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Start worker (separate terminal)
arq app.worker.WorkerSettings
```

</details>

<details>
<summary><strong>Mobile Setup</strong></summary>

```bash
cd teqlif/mobile

# Install dependencies
flutter pub get

# Generate localization files
flutter gen-l10n

# iOS
flutter run -d ios

# Android
flutter run -d android

# Android release build
fastlane android build
```

</details>

<details>
<summary><strong>Database Commands</strong></summary>

```bash
# Create new migration (REQUIRED after every model change)
alembic revision --autogenerate -m "description"

# Apply migrations
alembic upgrade head

# Rollback one step
alembic downgrade -1

# View migration history
alembic history --verbose
```

> [!WARNING]
> Always run `alembic revision --autogenerate` after every model file change. Skipping this will cause schema mismatch in production.

</details>

---

## 📐 Developer Guidelines

> [!TIP]
> These rules are binding for both backend and mobile. PRs containing violations will not be merged.

<details>
<summary><strong>Backend Rules</strong></summary>

- ✅ **Full async** — All I/O must use `async/await`; `time.sleep()` is forbidden
- ✅ **Modular routers** — Never bloat `main.py`; new domain → new file under `/app/routers/`
- ✅ **Input sanitization** — `sanitizer.py` must be applied to all user-provided strings
- ✅ **ENV management** — All secrets through `config.py` (Pydantic Settings); hard-coded secrets are forbidden
- ✅ **Error logging** — Unexpected exceptions must be forwarded via `sentry_sdk.capture_exception()`
- ✅ **Migration required** — Every model change requires an Alembic migration; zero exceptions

</details>

<details>
<summary><strong>Mobile Rules</strong></summary>

- ✅ **Service layer** — All API calls go through `/services/*.dart`; HTTP calls inside widgets are forbidden
- ✅ **Widget splitting** — Screens exceeding 300 lines must be broken into sub-widgets
- ✅ **Color management** — Use `Theme.of(context)` or `kPrimary`; hard-coded `Colors.white` is forbidden
- ✅ **Keyboard handling** — All form screens must handle keyboard via `global_keyboard_accessory.dart` or `resizeToAvoidBottomInset`
- ✅ **Performance** — Prefer `StreamBuilder` / localized state over full-screen `setState` for list updates

</details>

<details>
<summary><strong>Web Rules</strong></summary>

- ✅ **No frameworks** — React, Vue, and Tailwind are not allowed; Vanilla JS + plain CSS only
- ✅ **DOM performance** — Update only the changed element; never wipe and recreate the entire list
- ✅ **Mobile-first** — Responsive with `grid` + `flexbox` + `media queries`
- ✅ **WebSocket reconnect** — Auto-reconnect on disconnect with user-facing indicator

</details>

---

## 🎨 Design System

| Token | Color | Hex | Usage |
|---|---|:---:|---|
| `kPrimary` | 🟦 Cyan-500 | `#06B6D4` | Primary button, accent, active icons |
| `Dark BG` | ⬛ Slate-900 | `#0F172A` | Page background |
| `Surface` | ⬛ Slate-800 | `#1E293B` | Cards, panels, bottom sheets |
| `Border` | ⬛ Slate-700 | `#334155` | Dividers |
| `Text Primary` | ⬜ Slate-100 | `#F1F5F9` | Main text |
| `Text Secondary` | 🔘 Slate-400 | `#94A3B8` | Secondary / caption text |
| `Success` | 🟩 Green-600 | `#16A34A` | Success messages, co-host promotion |
| `Warning` | 🟧 Amber-600 | `#D97706` | Warnings, mute notification |
| `Error` | 🟥 Red-500 | `#EF4444` | Errors, kick notification |
| `Live` | 🟥 Red-500 | `#EF4444` | LIVE badge |
| `CoHost` | 🌊 Cyan-400 | `#22D3EE` | Co-host username highlight |

---

<div align="center">

**⚡ Teqlif** — Live. Real. Instant.

*Made with ❤️ in Turkey*

</div>
