# Teqlif — İlan Ver, Sat, Kazan

Teqlif, düşük gecikmeli etkileşim ve yüksek ölçeklenebilirlik odaklı tasarlanmış, modern bir gerçek zamanlı açık artırma ve ilan platformudur. Sistem, güçlü bir asenkron backend, hafif bir web frontend ve çok platformlu bir mobil uygulama (Flutter) arasında bölünmüştür.

## 🏗 Sistem Mimarisi

Teqlif, kullanıcı etkileşimi, gerçek zamanlı koordinasyon ve kalıcı veri depolama arasındaki sorumlulukları ayıran modern bir yığın kullanır.

```mermaid
graph TB
    subgraph Clients ["İstemci Katmanı"]
        Mobile["Flutter Mobil Uygulama"]
        Web["Vanilla JS Web Uygulaması"]
    end

    subgraph LB ["Ingress Katmanı"]
        Nginx["Nginx Reverse Proxy"]
    end

    subgraph Application ["Uygulama Katmanı (FastAPI)"]
        API["REST API Worker'lar"]
        WS["WebSocket Yöneticileri"]
    end

    subgraph RTC ["Gerçek Zamanlı Koordinasyon"]
        RedisPubSub["Redis Pub/Sub (Olay Veriyolu)"]
        RedisCache["Redis Bellek (Sıcak Durum)"]
        LiveKit["LiveKit SFU (WebRTC)"]
    end

    subgraph Data ["Kalıcılık Katmanı"]
        Postgres[(PostgreSQL)]
        FileSystem["Yerel Depolama (/uploads)"]
    end

    Mobile --> Nginx
    Web --> Nginx
    Nginx --> API
    Nginx --> WS
    Nginx --> LiveKit
    
    API --> RedisCache
    WS --> RedisPubSub
    API --> Postgres
    API --> FileSystem
    WS --> RedisCache
    
    RedisPubSub -- "Yayın" --> WS
```

---

## ⚡ Gerçek Zamanlı Açık Artırma Akışı

Aşağıdaki diyagram, bir kullanıcının mobil cihazından gelen bir teklifin, Redis'teki atomik doğrulamadan geçerek tüm istemcilere eşzamanlı olarak nasıl yayıldığını göstermektedir.

```mermaid
sequenceDiagram
    participant User as Teklif Veren (Mobil/Web)
    participant API as FastAPI Worker
    participant Redis as Redis (Lua Script)
    participant PubSub as Redis Pub/Sub
    participant WS as WebSocket Yöneticileri (Tüm Worker'lar)
    participant Clients as Tüm Bağlı Kullanıcılar

    User->>API: POST /api/auction/{id}/bid {amount: 1500}
    API->>Redis: EVAL bid_script.lua {1500, user_id}
    Note over Redis: Atomik Kontrol: Mevcut teklif < 1500<br/>Yeni en yüksek teklifi ve kullanıcıyı set et
    Redis-->>API: {ok: 1, current_bid: 1500}
    
    API->>PubSub: PUBLISH auction_broadcast {stream_id, new_state}
    API-->>User: 200 OK (Teklif kabul edildi)

    PubSub-->>WS: Mesaj Alındı (Tüm Worker'lar)
    WS-->>Clients: WebSocket: {"type": "state", ...}
```

---

## 📊 Veri Tabanı Şeması (ER Diyagramı)

İlişkisel şema; kullanıcıların, ilanların ve gerçek zamanlı yayınların sıkı bir şekilde entegre olduğu bir sosyal ticaret yapısını desteklemek üzere tasarlanmıştır.

```mermaid
erDiagram
    USER ||--o{ LISTING : "sahibi"
    USER ||--o{ LIVE_STREAM : "yayıncısı"
    USER ||--o{ AUCTION : "kazananı"
    USER ||--o{ MESSAGE : "gönderir/alır"
    USER ||--o{ FOLLOW : "takip eder"
    
    LISTING ||--o{ AUCTION : "ürün"
    LIVE_STREAM ||--o{ AUCTION : "içerir"

    USER {
        int id PK
        string username
        string email
        string hashed_password
        json notification_prefs
        string fcm_token
    }

    LISTING {
        int id PK
        int user_id FK
        string title
        text description
        float price
        boolean is_active
    }

    LIVE_STREAM {
        int id PK
        int host_id FK
        string room_name
        string title
        boolean is_live
        int viewer_count
    }

    AUCTION {
        int id PK
        int stream_id FK
        int listing_id FK
        float start_price
        float final_price
        int winner_id FK
        string status
    }
```

---

## 🔄 Açık Artırma Durum Makinesi

Durum geçişleri Redis'te yönetilir ve canlı oturum sırasında hiçbir verinin kaybolmaması için PostgreSQL'de kalıcı hale getirilir.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Active : Yayını Başlat (Host)
    Active --> Paused : Duraklat (Host)
    Paused --> Active : Devam Et (Host)
    Active --> Ended : Teklifi Kabul Et / Durdur (Host)
    Paused --> Ended : Durdur (Host)
    Ended --> [*] : Tabloya Kaydedildi
```

---

## 🚀 Kurulum ve Dağıtım

Teqlif, standart bir Linux ortamında aşağıdaki bileşenlerle çalışır:

- **Backend**: FastAPI + Uvicorn (Systemd ile yönetilir).
- **Frontend**: Vanilla JS (Nginx tarafından sunulur).
- **Real-time**: Redis (Pub/Sub & Cache) + LiveKit SFU.
- **Veri Tabanı**: PostgreSQL.
- **Edge**: Nginx (SSL Sertifikası ve Proxy).
