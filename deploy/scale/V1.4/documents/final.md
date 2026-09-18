# Teqlif Scale V1.4 — Kapsamlı Mimari ve Uygulama Belgesi

> **Uygulama tarihi:** 2026-09-17 / 2026-09-18
> **Durum:** Aktif (production)
> **Önceki sürüm:** `deploy/scale/V1.3/`
> **Kaynak dosyalar:** `deploy/scale/V1.4/`, `deploy/scale/resources/` (Deprecated, V1.4 klasörleri altında toplandı)

---

## 1. Genel Bakış

Scale V1.4, Teqlif'in "Monolithic" dönemini kapatarak tamamen **Core-Edge (Merkez-Kenar) Mimarisine** geçtiği en büyük evrimdir. V1.3'ün 4-Node yapısı 6-Node'a çıkarılarak, Medya (WebRTC/MinIO) yükleri ile İşlem/Veritabanı (API/DB) yükleri birbirinden %100 izole edilmiştir (Bulkhead Pattern).

| Rol | V1.3 | V1.4 (Yeni) |
|---|---|---|
| L7 Edge Proxy & Rate Limit | gateway | gateway |
| **Edge 1** (LiveKit, MinIO) | node1 (Her şey buradaydı) | **node1** (Saf Medya ve Storage) |
| **Edge 2** (LiveKit, MinIO) | — | **node4** (node1'in ikizi) |
| **Core** (API, Worker, DB) | node1 (Hepsi bir aradaydı) | **node5** (Sadece işlem ve veri) |
| Monitoring, Staging & Backup | node3 | node3 (7 Hedefli Scrape) |
| AI Proxy & DNS Failover | node2 | node2 |

### V1.4 Motivasyonları:
1. **Bulkhead (Bölme) İzolasyonu:** PostgreSQL ve Clickhouse'un (veya AI modellerinin) CPU/RAM tüketimi yüzünden, aktif LiveKit ses/video oturumlarının kesintiye uğramasını engellemek.
2. **Yatay Ölçeklenebilirlik (Horizontal Scaling):** Medya yükü arttıkça yeni "Edge" sunucuları (Node4 gibi) ekleyebilmek; API yükü arttıkça "Core" sunucularını büyütebilmek.
3. **Güvenlik (Zırhlı Ağ):** Veritabanlarının (Postgres, Clickhouse, Redis Core) dış dünyayla olan bağlantısını %100 keserek yalnızca WireGuard üzerinden hizmet vermesini sağlamak.

### V1.4 ile Gelen Kritik Değişiklikler

| # | Değişiklik | Etki |
|---|---|---|
| 1 | **Node5 (Core)** Eklendi | FastAPI, ARQ Worker'lar, PostgreSQL ve Clickhouse Node1'den sökülüp Node5'e taşındı. |
| 2 | **Node4 (Edge 2)** Eklendi | Node1 ile aynı donanıma sahip ikinci bir LiveKit SFU ve MinIO Storage sunucusu eklendi. |
| 3 | Gateway Yönlendirmesi | Nginx upstream bloğu API trafiğini Node1 yerine doğrudan Node5 (10.10.0.5) WireGuard tüneline yönlendirdi. |
| 4 | Redis'in Parçalanması | Monolitik Redis üçe bölündü: Edge1 Cache, Edge2 Cache ve Core PubSub/Storage. |
| 5 | **edge-metrics-agent** | Node1 ve Node4'e kurulan Python tabanlı daemon. Kendi donanım (RAM/CPU/Net) verilerini Node5 Redis'e iletir (Yük dengeleme algoritması için hazırlık). |
| 6 | Veritabanı Dışa Kapatıldı | Postgres ve Redis portları (5432, 6379) Firewall üzerinden sadece wg0 (WireGuard) trafiğine izin verecek şekilde izole edildi. |
| 7 | MinIO Standalone Modu | Edge1 ve Edge2 üzerinde MinIO'lar, Cluster yerine birbirini tanımayan iki ayrı Standalone server (%80 Quota limitli) olarak yapılandırıldı. |
| 8 | **test_all.sh (Pentest/Health)** | Sistem sağlık kontrol scripti tam bir DevOps Hack testine dönüştürüldü. Auth bypass, Port isolation, Log analizi ve OOM (Swap) testleri eklendi. |
| 9 | Prometheus Target Güncellemesi | Node3 Prometheus ayarları 4 hedeften 7 hedefe (Gateway + 5 Node + Localhost) çıkarılarak tüm 6 sunucu ağa dahil edildi. |
| 10| 6-Node WireGuard Mesh | WireGuard topolojisi 4'ten 6'ya çıkarıldı. Her sunucu diğer 5'ine peer olarak eklendi. |

---

## 2. Donanım Dağılımı

### node1 — OVHcloud (Edge 1 — Medya & Storage)
*   **Donanım:** 6 Core Intel Haswell, 11.4 GB RAM + 8 GB Swap, 98.3 GB NVMe
*   **Ağ:** 2 Gbps unmetered
*   **WireGuard:** 10.10.0.1
*   **V1.4 Değişimi:** Veritabanları ve API tamamen silindi. Yalnızca LiveKit (UDP 50000-60000) ve MinIO (9010) barındırıyor.

### node4 — OVHcloud (Edge 2 — Medya & Storage) **[YENİ]**
*   **Donanım:** 6 Core Intel Haswell, 11.4 GB RAM + 8 GB Swap, 98.3 GB NVMe
*   **Ağ:** 2 Gbps unmetered
*   **WireGuard:** 10.10.0.6
*   **Rol:** Node1'in birebir klonu. Artan medya trafiğini karşılayacak.

### node5 — ZAP-Hosting (Core 1 — Backend & Veritabanı) **[YENİ]**
*   **Donanım:** 4 Core EPYC, 7.8 GB RAM + 8 GB Swap, 50 GB SSD
*   **Ağ:** 1 Gbps unmetered
*   **WireGuard:** 10.10.0.5
*   **Rol:** İşlemci ve Bellek gücünü (FastAPI, PostgreSQL, Clickhouse) tek başına göğüsler. Dışarıya hiçbir portu açık değildir.

### gateway — netcup (L7 Proxy & Güvenlik)
*   **Donanım:** 2 Core, 2 GB RAM
*   **WireGuard:** 10.10.0.2
*   **V1.4 Değişimi:** Upstream trafiğini Node1'den (10.10.0.1) Node5'e (10.10.0.5) çevirdi. SSL sonlandırma ve Rate Limiting'e devam ediyor.

### node3 — ZAP-Hosting (Monitor, Staging & Backup)
*   **Donanım:** 4 Core EPYC, 3.8 GB RAM
*   **WireGuard:** 10.10.0.4
*   **V1.4 Değişimi:** Prometheus config güncellenerek Node4 ve Node5 (wg0 üzerinden) scraping ağına dahil edildi.

### node2 — VPSHostingService (AI Proxy & Failover)
*   **Donanım:** 1 Core, 1 GB RAM (ABD)
*   **WireGuard:** 10.10.0.3
*   **Değişim Yok:** Groq/Gemini bypass işlemini sürdürüyor.

---

## 3. Topoloji ve Trafik Akışı (V1.4)

```text
                     ┌──────────────────────────────────────────────┐
  İnternet           │             CLOUDFLARE EDGE                  │
                     │  (SSL Proxy, WAF, DNS Routing)               │
                     └─────────────┬─────────┬─────────┬────────────┘
                                   │         │         │
                        (API: /api/*)     (S3 API)   (S3 API)
                                   │         │         │
                   ┌───────────────▼─┐    ┌──▼──┐   ┌──▼──┐
                   │ gateway (Nginx) │    │node1│   │node4│ (Cloudflare DNS By-pass)
                   │  10.10.0.2      │    │MinIO│   │MinIO│ (minio1.teqlif.com vb.)
                   └───────┬─────────┘    └─────┘   └─────┘
                           │
                 (wg0 - 10.10.0.5)
                           │
      ┌────────────────────▼────────────────────┐
      │          node5 (Core 1)                 │
      │   FastAPI Orchestrator :8000            │
      │   PostgreSQL           :5432            │
      │   Clickhouse           :8123            │
      │   Redis Core           :6379            │
      │   ARQ Workers                           │
      └────────────────────┬────────────────────┘
                           │ (PubSub & WebSocket Olayları)
                  ┌────────┴────────┐
                  │                 │
             ┌────▼────┐       ┌────▼────┐
             │  node1  │       │  node4  │
             │ (Edge1) │       │ (Edge2) │
             │ LiveKit │       │ LiveKit │
             │  SFU    │       │  SFU    │
             │  (UDP)  │       │  (UDP)  │
             └─────────┘       └─────────┘
                  ▲                 ▲
                  │  (Doğrudan UDP) │
                  └──────İstemci────┘
```

---

## 4. Servis Dağılım Matrisi

| Servis | Node1 (Edge1) | Node4 (Edge2) | Node5 (Core) | Node3 (Monitor/Staging) | Gateway |
|---|---|---|---|---|---|
| **FastAPI (Prod)** | ❌ (Taşındı) | ❌ | ✅ | ❌ | ❌ |
| **ARQ Workers** | ❌ (Taşındı) | ❌ | ✅ | ❌ | ❌ |
| **PostgreSQL** | ❌ (Taşındı) | ❌ | ✅ | ✅ (Staging) | ❌ |
| **Clickhouse** | ❌ (Taşındı) | ❌ | ✅ | ❌ | ❌ |
| **Redis** | ✅ (Cache) | ✅ (Cache) | ✅ (Core) | ✅ (Staging) | ❌ |
| **LiveKit SFU** | ✅ | ✅ | ❌ | ✅ (Staging) | ❌ |
| **MinIO** | ✅ | ✅ | ❌ | ✅ (Staging) | ❌ |
| **edge-metrics-agent** | ✅ | ✅ | ❌ (Veri Alıcısı)| ❌ | ❌ |
| **Prometheus/Loki** | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Nginx Public** | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 5. Güvenlik Katmanları ve Pentest Testleri (V1.4)

### 1. Zırhlı İzolasyon (Firewall)
*   Tüm veritabanları (PostgreSQL, Redis, Clickhouse) UFW üzerinden dış dünyaya %100 kapatılmıştır.
*   Yalnızca `wg0` (WireGuard) interface'i üzerinden gelen bağlantılar (10.10.0.0/24 subneti) kabul edilmektedir.
*   **Pentest Doğrulaması:** `test_all.sh` scripti dışarıdan 5432 ve 6379 portlarına `nc` ile saldırmayı dener. UFW'nin bu paketleri başarılı bir şekilde "drop" ettiği sistem testinden geçmiştir.

### 2. Redis Authentication (ACL)
*   Redis izolasyonla yetinilmeyip uygulama katmanında da AUTH ile korunmaktadır.
*   **Pentest Doğrulaması:** `test_all.sh` `redis-cli ping` gönderir. Eğer Redis `NOAUTH` hatası (Şifre istiyor) döndürüyorsa test başarılı (PASS) sayılır.

### 3. Hassas Veri Sızıntısı Engeli (Sensitive Data Exposure)
*   Nginx Gateway üzerinde `/.env`, `/.git`, `/.github` gibi kritik dizin ve dosyalara yönelik direkt erişim istekleri engellenmiştir.
*   **Pentest Doğrulaması:** Script, dışarıdan curl ile `.env` çekmeye çalışır ve `HTTP 404 (veya 403)` bekler.

### 4. SSH Güvenliği
*   Kökten (Root) parola ile girişe karşı fail2ban aktiftir.

---

## 6. Edge Metrics Daemon (Yeni Bileşen)

**Konum:** Node1 ve Node4 (`/var/www/teqlif.com/backend/scripts/edge_metrics_agent.py`)
**Çalışma Mantığı:**
*   Bir Systemd servisi (`edge-metrics-agent.service`) olarak çalışır.
*   Her 3 saniyede bir CPU, RAM, Disk, Ağ (Rx/Tx) metriklerini toplar.
*   Bu veriyi WireGuard üzerinden Node5'teki Core Redis sunucusuna (`teqlif_edge_metrics:node1` anahtarıyla) yazar.
*   **Amaç:** İleriki fazlarda (V1.5) FastAPI Orchestrator'ın (Node5), odaya yeni katılan bir kullanıcıyı "Hangi Edge sunucusuna yönlendireyim?" sorusuna anlık yük durumuna bakarak karar vermesini sağlamaktır.

---

## 7. Dağıtım ve Yönetim (Workflow)

### Bootstrap Mimarisi (Idempotency)
V1.4 ile bootstrap scriptleri (`deploy/scale/V1.4/`) daha modüler ve hataya dayanıklı hale getirildi. 
*   **UFW Koruması:** Scriptler artık `sudo ufw allow in on wg0 to any` kuralını otomatik basarak WireGuard içi iletişimi (Monitoring scraping) serbest bırakır.
*   **Otomatik Servis Yönlendirmeleri:** Env dosyalarında Node IP'leri `10.10.0.x` olarak standartlaştı.

### WireGuard Anahtar (Kimlik) Yönetimi
WireGuard public keylerinin asimetrik şifreleme kurallarına göre repoda açıkça tutulması (Public) güvenlidir. Ancak anahtarlardan birinin değişmesi durumunda mesh yapısını onarmak için özel bir araç eklendi:
`sudo bash deploy/scale/V1.4/scripts/repair_wireguard.sh`
*   Sunucunun *kendi gizli anahtarını (Private Key)* mevcut `/etc/wireguard/wg0.conf` dosyasından okur ve korur.
*   Repodaki V1.4 şablonunu kopyalar, mevcut gizli anahtarı içine enjekte eder.
*   Yalnızca *Peer* kimliklerini (diğer sunucuların Public Key'lerini) günceller ve ağı onarır.

### Pentest (Health Check) Aracı
`bash deploy/scale/V1.4/scripts/test_all.sh`
Mimarinin tam durumunu gösteren 113 adımlık kusursuzlaştırılmış test motoru. SSH bağlantılarından veritabanı canlılığına, UFW kurallarından TLS sertifika günlerine kadar tarar.

**Sonuç:** `PASS: 113, FAIL: 0`. Sistem V1.4 ölçeğinde resmi olarak Prod ortamına geçmiştir.
