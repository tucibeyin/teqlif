<div align="center">

<img src="https://img.shields.io/badge/-%E2%9A%A1%20Teqlif-06B6D4?style=for-the-badge&labelColor=0F172A&color=06B6D4" height="48" alt="Teqlif"/>

### The Ultimate Live-Streaming C2C Marketplace & Real-Time Auction Engine

<br/>

[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-asyncpg-336791?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![Redis](https://img.shields.io/badge/Redis-Pub%2FSub-DC382D?style=flat-square&logo=redis&logoColor=white)](https://redis.io)
[![LiveKit](https://img.shields.io/badge/LiveKit-WebRTC-00A0E3?style=flat-square)](https://livekit.io)
[![Grafana](https://img.shields.io/badge/Grafana-Monitoring-F46800?style=flat-square&logo=grafana&logoColor=white)](https://grafana.com)
[![Sentry](https://img.shields.io/badge/Sentry-Tracing-362D59?style=flat-square&logo=sentry&logoColor=white)](https://sentry.io)

</div>

---

> **Note:** This is the comprehensive **ARC42 End-to-End Architectural Documentation** of the Teqlif Platform, enhanced with GitHub-native Mermaid diagrams, ER schemas, and data flow visuals.

## 1. Introduction and Vision

**Teqlif** is a hyper-scalable, multi-platform C2C marketplace tailored for the Turkish ecosystem. It bridges the gap between traditional e-commerce and interactive entertainment by integrating **low-latency live streaming, real-time auctions, 1-on-1 VoIP calls, and an embedded virtual economy (Tuci).** 

---

## 2. End-to-End System Architecture

Teqlif operates on a micro-service-inspired monolithic backend with a strict separation of concerns, orchestrated via Nginx and monitored by Prometheus/Grafana and Sentry.

```mermaid
graph TB
    subgraph CLIENTS["📱 Client Layer"]
        MOB["Flutter Mobile App\n(Teq UI, CallKit)"]
        WEB["Admin Panel\n(Vanilla JS)"]
    end

    subgraph EDGE["🌐 Edge & Security"]
        NGINX["Nginx\nReverse Proxy & SSL"]
        CF["Cloudflare Turnstile\n(Bot Protection)"]
    end

    subgraph BACKEND["⚙️ Backend System (FastAPI)"]
        API["REST & WS API\n(uvicorn async)"]
        WORKER["ARQ Worker\n(Cron & Heavy Tasks)"]
    end

    subgraph REALTIME["⚡ Real-Time Mesh"]
        LK["LiveKit Cloud\n(WebRTC SFU)"]
        RD["Redis\n(Pub/Sub, Rate Limit)"]
    end

    subgraph AI_ML["🧠 AI & ML Engine"]
        MODELS["ALS, CLIP, NER\nNSFW, Churn Models"]
    end

    subgraph DATA["🗄 Storage Layer"]
        PG["PostgreSQL 14+\n(asyncpg)"]
        FAISS["FAISS Index\n(Vector Search)"]
    end

    MOB --> EDGE
    WEB --> EDGE
    EDGE --> API
    API --> WORKER
    API <--> REALTIME
    API <--> AI_ML
    API <--> DATA
    WORKER <--> AI_ML
    WORKER <--> DATA
    MOB <-->|"WebRTC"| LK
```

---

## 3. Data Flow & Core Processes

<details>
<summary><strong>🔨 Real-time Auction — Bid Flow</strong></summary>

```mermaid
sequenceDiagram
    actor User
    participant API as FastAPI Router
    participant RL as Rate Limiter (SlowAPI)
    participant REDIS as Redis (Lua Script)
    participant PG as PostgreSQL
    participant PS as Pub/Sub
    participant WS as WebSocket Manager
    participant Others as All Viewers

    User->>API: POST /api/auction/{id}/bid
    API->>RL: Rate limit check (2/s)
    API->>REDIS: Atomic Lua Script (auction active? bid > current?)
    alt Invalid bid
        REDIS-->>User: 400 Bad Request
    end
    REDIS->>PG: Write bid record
    PG-->>REDIS: OK
    REDIS->>PS: PUBLISH auction_broadcast
    PS->>WS: pubsub_listener triggered
    WS->>Others: 🔔 New bid broadcasted (sub-second)
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
    Host->>LK: room.connect(token) (Publish Video/Audio)

    Viewer->>API: POST /api/streams/{id}/join
    API->>LK: Get viewer token
    Viewer->>LK: room.connect(token) (TrackSubscribedEvent)
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
        MOD["Moderation (kick/mute)"]
    end

    subgraph REDIS["Redis Pub/Sub"]
        AB["auction_broadcast"]
        CB["chat_broadcast"]
    end

    subgraph MAIN["Async Listeners (FastAPI)"]
        PL["pubsub_listener"]
        CL["chat_pubsub_listener"]
    end

    subgraph CLIENTS["Connected Clients"]
        M1["📱 Mobile #1"]
        W1["🌐 Web #1"]
    end

    BID --> AB
    CHAT --> CB
    MOD --> CB
    AB --> PL
    CB --> CL
    PL --> M1 & W1
    CL --> M1 & W1
```
</details>

<details>
<summary><strong>📞 VoIP 1-on-1 Call Signaling</strong></summary>

```mermaid
sequenceDiagram
    actor Caller
    participant API as FastAPI
    participant LK as LiveKit
    participant APNS as Apple PushKit
    actor Callee
    
    Caller->>API: POST /api/calls/start
    API->>LK: Create Private Room
    API->>APNS: High Priority VoIP Push
    APNS->>Callee: Wake up device (Native Call Screen)
    Callee->>LK: Answers & Connects to WebRTC Room
```
</details>

---

## 4. Artificial Intelligence & Machine Learning (AI/ML)

Teqlif goes beyond standard CRUD by integrating multiple specialized AI pipelines natively into the Python backend.

| Model / Algorithm | Purpose & Capability |
|---|---|
| **Semantic Search (FAISS)** | Uses `sentence-transformers` (all-MiniLM-L6-v2) to convert listings into dense vectors for L2 distance similarity queries, far outperforming standard SQL. |
| **Multimodal Search (CLIP)** | Integrates **OpenAI CLIP** allowing users to search via images (image-to-text / text-to-image). |
| **Recommendation Engine (ALS)** | Employs **Alternating Least Squares (ALS)** for collaborative filtering to personalize the user's home feed based on implicit feedback (clicks, bids). |
| **Turkish NLP & NER** | Custom pipeline to extract Brands, Locations, and Specs from unstructured Turkish listing texts. |
| **Churn Prediction** | Analyzes engagement drops to predict which users might leave, triggering retention campaigns. |
| **Image Moderation (pHash & NSFW)** | Automated scanning for NSFW content and perceptual hashing to instantly block spam duplicate uploads. |
| **Trust Scoring** | Graph-based algorithm evaluating a user's network to assign a public Trust/Influence Score. |

<details>
<summary><strong>🧠 ML Feed Generation (ALS + FAISS)</strong></summary>

```mermaid
sequenceDiagram
    actor User
    participant API as FastAPI
    participant RD as Redis (Cache)
    participant ALS as feed_als_ml
    participant PG as PostgreSQL
    
    User->>API: GET /api/feed
    API->>RD: Check cached personalized feed
    alt Cache Miss
        API->>ALS: Generate recommendations for User
        ALS->>PG: Fetch user interaction matrix
        ALS-->>API: List of recommended Listing IDs
        API->>RD: Cache for 5 mins
    end
    API->>PG: Fetch listing details
    API-->>User: JSON Feed
```
</details>

---

## 5. Mobile Client Architecture (Flutter)

The mobile application relies on **Flutter 3.x** and **Riverpod** for state management, entirely powered by the custom **Teq UILibrary**.

<details>
<summary><strong>🧭 Navigation Map</strong></summary>

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
    SEARCH --> SWIPE["SwipeLiveScreen\n(TikTok-style PageView)"]
    LIVE --> SWIPE
    PROFILE --> HOST["HostStreamScreen\n(Camera + Microphone)"]
    DETAIL --> PUBLIC["PublicProfileScreen"]
    PUBLIC --> VIEWER["ViewerStreamScreen\n(Single stream)"]
```
</details>

<details>
<summary><strong>🎨 Teq UILibrary & Structure</strong></summary>

```text
mobile/lib/
├── config/                 # theme.dart (TeqColors, TeqTypography)
├── models/                 # 17+ strongly-typed Dart models (Listing, StreamOut)
├── services/               # API logic (auth_service, ws_service, auction_service)
├── providers/              # Riverpod State Providers
├── screens/                # Flutter UI Screens (SwipeLiveScreen, HostStreamScreen)
└── ui_library/             # 🛠 THE TEQ DESIGN SYSTEM
    ├── teq_button.dart     # Micro-animated interactions
    ├── teq_snackbar.dart   # Non-blocking overlays
    └── teq_card.dart       # Standardized premium containers
```
</details>

---

## 6. Database Schema (PostgreSQL)

The system utilizes an advanced, strictly normalized PostgreSQL schema with over 20 tables. All relationships are managed asynchronously via `asyncpg` and SQLAlchemy 2.0. Soft deletes are enforced using the `status` Enum (`'active'`, `'deleted'`) to protect ML integrity.

<details>
<summary><strong>🗄 View Entity-Relationship (ER) Diagram</strong></summary>

```mermaid
erDiagram
    users {
        int id PK
        string username UK
        string email UK
        string hashed_password
        bool is_verified
        datetime created_at
    }

    listings {
        int id PK
        int user_id FK
        decimal price
        string status "Enum: active, deleted"
        bool is_live
        vector embedding "FAISS/pgvector"
    }

    auctions {
        int id PK
        int listing_id FK
        decimal current_price
        int current_winner_id FK
        datetime end_time
    }

    bids {
        int id PK
        int auction_id FK
        int user_id FK
        decimal amount
    }

    streams {
        int id PK
        int host_id FK
        string livekit_room_id
        int viewer_count
    }
    
    analytics {
        int id PK
        int user_id FK
        string event_type
        json metadata
    }
    
    wallet_transactions {
        int id PK
        int user_id FK
        decimal tuci_amount
        decimal fiat_amount
    }

    users ||--o{ listings : "creates"
    users ||--o{ streams : "broadcasts"
    users ||--o{ bids : "places"
    users ||--o{ wallet_transactions : "owns"
    listings ||--o| auctions : "hosts"
    auctions ||--o{ bids : "receives"
    users ||--o{ analytics : "generates"
```
</details>

---

## 7. Global API Map

<details>
<summary><strong>🌐 View Core Endpoints</strong></summary>

| Category | Method | Endpoint | Description |
|---|---|---|---|
| **Auth** | `POST` | `/api/auth/register` | Register (Cloudflare Turnstile CAPTCHA required) |
| | `POST` | `/api/auth/login` | Retrieve JWT |
| **Listings** | `GET` | `/api/listings` | Fetch feed (Uses FAISS / ALS if authenticated) |
| | `POST` | `/api/listings/{id}/offer` | Submit a direct price offer |
| **Auctions** | `POST` | `/api/auction/{id}/bid` | **Place bid** (Redis Lua script, Rate Limit: 2/s) |
| | `WS` | `/ws/auction/{stream_id}` | Live bid broadcast stream |
| **Streams** | `POST` | `/api/streams` | Start broadcast (Provisions LiveKit token) |
| | `WS` | `/ws/stream/{id}` | Chat & Viewer count syncing |
| **Calls** | `POST` | `/api/calls/start` | Initiates 1-on-1 VoIP call (APNs PushKit) |
| **Wallet** | `GET` | `/api/wallet/sync` | Sync Tuci/Fiat rates via TCMB |

</details>

---

## 8. Observability, Security & Deployment

### 8.1 Observability Stack
- **Prometheus & Grafana:** Middleware intercepts all FastAPI requests. Grafana dashboards track Request Latency, Error Rates, WebSocket loads, and LiveKit active rooms.
- **Sentry (`sentry-sdk`):** Integrated in both Flutter and FastAPI for distributed error tracing and performance bottleneck tracking.

### 8.2 Security Guardrails
- **Rate Limiting (`slowapi`):** Strict Redis-backed IP rate limits.
- **XSS Mitigation (`bleach`):** `SecurityMiddleware` passes all inputs through Bleach to strip malicious scripts. `better-profanity` cleans live chat streams.
- **Access Control:** Role-Based Access Control via JWT. Ownership checks (e.g., *does this user own this listing?*) enforce multi-tenant isolation.

### 8.3 Deployment (CI/CD)
- **Infrastructure:** Dedicated Ubuntu VPS running Nginx (SSL), Systemd for FastAPI & ARQ Worker.
- **CI/CD:** `fastlane` automates Flutter iOS/Android builds and store submissions. `alembic upgrade head` secures DB drift.

---
*End of ARC42 Documentation.*
