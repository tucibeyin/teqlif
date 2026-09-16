# Teqlif Scale V1.4 - Uçtan Uca Uygulama ve Görev Planı (plan.md)

Bu belge, `V1.4/teqlif_architectural_decisions.md` dosyasındaki mimari kararları, "Clean Architecture", "Clean Code" ve "Sıfır Statik Veri" prensiplerine tam sadık kalarak koda ve sunuculara dökeceğimiz adım adım uygulama planıdır. Görevler (Phase'ler) birbirine bağımlıdır ve sırayla çalıştırılacaktır.

---

## 🎯 Hedef Topoloji ve Bileşen Dağılımı (V1.4 Node Matrix)

Bu matris, `teqlif/README.md` (V1.3 Mimari Belgesi) ve `deploy/scale/resources` dosyalarındaki kaynak kod seviyesindeki analizlere dayanarak Core-Edge (V1.4) yapısına geçişin kesin, teknik ve son halini sunar.

### 1. Servis ve Rol Dağılımı (V1.3 → V1.4)

| Node | Donanım (YABS) | V1.3 Rolü & Yükleri (Mevcut) | V1.4 Rolü & Yükleri (Yeni) | Teknik Operasyon (Görevler) |
| :--- | :--- | :--- | :--- | :--- |
| **Node1** | OVH (DE)<br>11.4 GB RAM<br>6 Core | **Monolithic Prod (SPOF)**<br>`teqlif` (FastAPI), `arq-worker`<br>`postgresql`, `clickhouse`<br>`redis-server` (Tüm Poollar)<br>`livekit`, `minio` | **Edge 1 (Saf Medya & Storage)**<br>`livekit` (İzole - WebRTC :7880)<br>`redis-server` (Sadece LiveKit için)<br>`minio` (Standalone İzole :9010)<br>`edge-metrics-agent` | 1. `teqlif`, `arq`, `postgresql`, `clickhouse` durdurulup Node5'e taşınacak.<br>2. Redis pool'ları (app, cache, pubsub) iptal edilecek.<br>3. MinIO İzole Standalone moda alınacak (%80 Quota). |
| **Node4** | OVH (DE)<br>11.4 GB RAM<br>6 Core | *(Sistemde Yok)* | **Edge 2 (Saf Medya & Storage)**<br>`livekit` (İzole - WebRTC :7880)<br>`redis-server` (Sadece LiveKit için)<br>`minio` (Standalone İzole :9010)<br>`edge-metrics-agent` | 1. Node4 WireGuard (10.10.0.x) ağına eklenecek.<br>2. Node1'in birebir ikizi olarak Edge medyası (SFU) kurulacak.<br>3. MinIO Standalone kurulacak (%80 Quota). |
| **Node5** | ZAP-Hosting<br>7.8 GB RAM<br>4 Core EPYC | *(Sistemde Yok)* | **Core 1 (Backend & DB Master)**<br>`teqlif` (FastAPI Orchestrator)<br>`teqlif-worker` (ARQ Default & Critical)<br>`postgresql` (Master)<br>`clickhouse` (1.5GB RAM Limitli)<br>`redis-server` (Core PubSub/Cache) | 1. WireGuard Mesh'e katılacak.<br>2. pg_dump ve CH verileri Node1'den buraya aktarılacak.<br>3. Sadece Core görevler yapacak (Monitor/Log almayacak). |
| **Gateway** | Netcup<br>1.9 GB RAM<br>2 Core | **Trafik & L7 Güvenlik**<br>`nginx` (:443 SSL Termination)<br>Cloudflare IP Allowlist<br>Rate Limiter (1800/dk) | **Trafik Yönlendirici (Gateway)**<br>`nginx` (Gateway)<br>`fail2ban` | 1. Nginx proxy_pass upstream IP'si Node5'e çevrilecek.<br>2. Sadece ters vekil (Gateway) görevini sürdürecek. Monitor servisleri Node3'te kalacak. |
| **Node3** | ZAP-Hosting<br>3.8 GB RAM<br>4 Core EPYC | **Staging, AI & Monitor**<br>`teqlif-staging`, `minio-staging`<br>`teqlif-ai-proxy` (İkincil)<br>`prometheus`, `loki`, `grafana` | **Monitor, Staging & AI Proxy**<br>`prometheus`, `loki`, `grafana`<br>`alertmanager`<br>`teqlif-staging`, `minio-staging`<br>`teqlif-ai-proxy` (İkincil) | **Değişiklik Yok:** Tüm sistemi bu node üzerinden gözlemleyeceğiz (Monitoring yığını burada kalacak). Gateway ve Node5 bu yükten muaf tutulacak. |
| **Node2** | RackNerd<br>1.4 GB RAM<br>1 Core | **AI & Failover (ABD IP)**<br>`teqlif-ai-proxy` (Birincil)<br>`cf-failover` daemon | **AI & Failover**<br>`teqlif-ai-proxy` (Birincil)<br>`cf-failover` daemon | **Değişiklik Yok:** Groq/Gemini bypass zincirinde ilk durak ve DNS A kaydı bekçisi olmaya devam edecek. |

### 2. Mimari Trafik ve Veri Akışı (Topoloji)
*   **HTTP/REST Trafiği:** 📱 İstemci → Cloudflare → Gateway (Nginx) → Node5 (FastAPI).
*   **WebSocket (Chat/Teklif):** 📱 İstemci → Cloudflare → Gateway → Node5 (FastAPI WS Manager). (Olaylar Node5'teki Redis Pub/Sub ile dağıtılır).
*   **WebRTC Medya (Video/Ses):** 📱 İstemci → Node1 veya Node4 (LiveKit UDP: 50000-60000). (Gateway ve CF Bypass edilir, doğrudan UDP atılır).
*   **Dosya/Medya (MinIO):** 📱 İstemci → Cloudflare → Gateway → Node1/Node4 (MinIO Cluster S3 API).
*   **AI Açıklama (Proxy Zinciri):** Node5 (FastAPI) → Node2 (Primary US) → Node3 (Secondary US) → Groq/Gemini.

### 3. Güvenlik ve Gözlemlenebilirlik (V1.4 Standartları)
*   **Spill-to-Disk Koruması:** Node5 üzerindeki ClickHouse OOM (Out-of-Memory) engellemek için agresif `max_memory_usage` parametreleriyle donatılacaktır.
*   **Metric Toplama:** Tüm node'larda `node_exporter` ve `promtail` çalışmaya devam edecek, ancak Edge (Node1, Node4) ağ kartı metrikleri (Rx/Tx) Node5'teki Orkestratöre WebSocket veya Redis üzerinden bildirilecektir.
*   **Ağ İzolasyonu (WireGuard):** Veritabanlarına (Postgres, Clickhouse, Redis Core) dışarıdan erişim tamamen kapalı kalacak, sadece `10.10.0.x` WireGuard overlay ağı üzerinden haberleşilecektir.

---

## 🟢 Faz 1: Altyapı Hazırlığı ve "Sıfırdan Yazım" (Clean State)
*Eski dizinler bozulmayacak, V1.4 için yepyeni bir altyapı paketi hazırlanacaktır.*

1. **V1.4 Kaynak (Resources) Dizinleri:** V1.3'ün kurulu düzenini (rollback güvenliğini) korumak adına eski `deploy/scale/resources/` dizini refactor EDİLMEYECEKTİR. Bunun yerine `deploy/scale/V1.4/{node}/resources/` formatında, tüm node'lar (node1, node2, node3, node4, node5, gateway) için tamamen V1.4'e özel yepyeni dizinler açılacaktır.
2. **Baştan Yazım ve Jenerik Repo Bağlantısı (Generic Pathing):** Scriptlerin içindeki eski `deploy/scale/resources/` yol bağımlılıkları tamamen koparılacaktır. Yeni yazılacak `.sh` dosyaları:
   - Kendi bulundukları `V1.4/{node}/resources/` klasörünü dinamik olarak (`RESOURCES_DIR="$(cd "$(dirname "$0")" && pwd)"`) çözümleyecek.
   - Tüm node'larda halihazırda (root yetkili `tucibeyin` kullanıcısı altında) bulunan `/var/www/teqlif.com` repo dizini baz alınarak, bu `RESOURCES_DIR` üzerinden 5 üst dizine (`../../../../..`) çıkılarak jenerik `REPO` değişkeni tanımlanacak. Böylece scriptler hardcode path kullanmadan evrensel (portable) çalışmaya devam edecektir.
3. **Network ve WireGuard Mesh (6-Node):** Yeni dizinler içinde oluşturulacak ağ haritası, Node4 (`10.10.0.6`) ve Node5 (`10.10.0.5`) sunucularını da kapsayacak şekilde (UFW port izinleri ve WireGuard şablonları) baştan kurgulanacaktır.
4. **"No Hardcoding" Şablonları:** Yeni oluşturulan `V1.4/{node}/resources/.env.*.template` dosyalarına dinamik değişkenler (Örn: `EDGE_LIVEKIT_URLS="wss://node1,wss://node4"`, `MINIO_STORAGE_QUOTA_PERCENT=80`) eklenecektir.

---

## 🟡 Faz 1.5: WireGuard 6-Node Mesh Ağının Kurulması (Kritik Network Topolojisi)
*V1.3'teki 4-Node ağının, V1.4 mimarisi için 6-Node olarak (Edge 2 ve Core dahil) baştan yazılması.*

1. **`resources/wg0.conf` Olarak Dağıtım:** V1.4 altyapı bağımsızlığı prensibine uygun olarak, ayrı bir klasör yerine her sunucunun kendi `deploy/scale/V1.4/{node}/resources/wg0.conf` dosyası oluşturulmuştur.
2. **IP Adreslemesi (10.10.0.x/24):**
   - `10.10.0.1`: Node1 (Edge 1 - 135.125.175.223)
   - `10.10.0.2`: Gateway (Proxy - 94.16.105.135)
   - `10.10.0.3`: Node2 (Worker - 198.12.123.33)
   - `10.10.0.4`: Node3 (Staging - 5.249.165.10)
   - `10.10.0.5`: Node5 (Core - 45.146.252.165)
   - `10.10.0.6`: Node4 (Edge 2 - 51.75.74.124)
3. **Template'lerin Oluşturulması:** Her sunucu için `[Peer]` tanımlarını (Full-Mesh) barındıran yepyeni `wg0.conf` şablonları kendi dizinlerine yazılmıştır.
4. **Güvenlik Entegrasyonu:** Daha önce yazdığımız UFW `allow in on wg0` kuralları, bu yapı sayesinde Node5'in (veritabanı) ve Node3'ün (staging) dış dünyaya tamamen kapalı ama kendi içlerinde iletişimde olmasını sağlayacaktır.

---

## 🟠 Faz 2: Kod Tabanı Refactor - Konfigürasyon Katmanı (Parser)
*Backend koduna girilir, monolitik yapı temizlenmeye başlanır.*

1. **`app/config.py` Revizyonu:** Tekil `livekit_url` ve `minio_endpoint` değişkenleri silinecek. Yerine `.env`'den okunan virgüllü string'leri Python List (Array) objelerine dönüştüren güvenli Pydantic validatörleri yazılacak. (Örn: `edge_livekit_urls: list[str]`).

---

## 🟠 Faz 3: Kod Tabanı Refactor - Edge Metrics Agent
*Node'ların kendi verilerini Node5'e bildirmesini sağlayan ajan.*

1. **Ajan Scriptinin Yazılması:** `scripts/edge_metrics_agent.py` oluşturulacak.
2. **Metrik Toplama Mantığı:** Linux `psutil` kullanılarak CPU, RAM, Network (Rx/Tx) ve Disk Doluluk Oranı (`df -h`) verileri toplanacak.
3. **Redis İletişimi:** Her 3 saniyede bir (süre `.env`'den alınır) bu veriler Node5'in Core Redis'ine (Örn: `edge:metrics:node4` key'iyle) yazılacak.

---

## 🔴 Faz 4: Kod Tabanı Refactor - Dinamik Orkestratör (Core Business Logic)
*Sistemin asıl "Beyni" olan servisin inşa edilmesi.*

1. **Orchestrator Sınıfı:** `app/services/stream_orchestrator.py` yaratılacak. (Clean Architecture: Sadece iş mantığı barındıracak).
2. **LiveKit Karar Mekanizması:** `get_best_livekit_node()` metodu yazılacak. Core Redis'ten Edge CPU ve Bant genişliği verilerini okuyup en boş olan Node URL'sini döndürecek.
3. **MinIO (Media Sharding) Karar Mekanizması:** `get_best_storage_node()` metodu yazılacak. Diski %80'in (veya `.env`'deki kotanın) altında olan ve en çok GB boş alanı olan Node'u seçecek.

---

## 🟣 Faz 5: Kod Tabanı Refactor - Servis ve Use-Case Entegrasyonları
*Orkestratörün sisteme bağlanması ve eski monolitik yapının tamamen sökülmesi.*

1. **`storage_service.py` Refactor:** Tek bir `_client` yerine, Orkestratör'den dönen Edge URL'ye göre dinamik olarak Minio istemcisi oluşturulacak/kullanılacak.
2. **MinIO Standalone Dosya Bütünlüğü:** Dosyalar Orkestratör'ün seçtiği tek bir hedefe tek parça yazılacak. Veritabanına (PostgreSQL) dosyanın konumu (`node_id` veya `url_prefix` olarak) kaydedilecek.
3. **`stream_utils.py` ve Use-Cases:** Canlı yayın başlatma (`start_stream`), katılma (`join_stream`) ve `cohost` işlemlerinde statik `settings.livekit_url` kullanımı silinecek; yerine Orkestratör'den gelen dinamik Edge adresi kullanılacak.

---

## ⚫ Faz 6: Canlıya Geçiş, Veri Göçü ve Edge İzolasyonu (Execution)
*Tüm kodlar test edildikten sonra sunucularda yapılacak operasyonlar.*

1. **Node5 (Core) Kurulumu:** V1.4 dizinindeki `bootstrap_node5.sh` çalıştırılacak. PostgreSQL Master, Core Redis ve ClickHouse (Kesin RAM sınırlarıyla) ayağa kaldırılacak.
2. **Veri Göçü:** Mevcut Node1'deki (V1.3) veritabanları (PG dump) ve eski MinIO dosyaları Node5 ve Node4'e aktarılacak.
3. **Edge'lerin Formatlanması:**
   - Node4 (Yeni) saf Edge medyası olarak V1.4 scriptiyle kurulacak. (İzole Local Redis, Standalone MinIO %80 quota, LiveKit).
   - Node1'in sırtındaki veritabanları ve core yükler silinip Node4'ün ikizi (Edge 1) haline getirilecek (Yine V1.4 scripti kullanılacak).
4. **Gateway Yönlendirmesi:** Gateway'in V1.4 dizinindeki Nginx konfigürasyonu değiştirilerek API trafiği tamamen Node5'e (Core) kaydırılacak. 

---
> **Not:** Her faz, bitiminde doğrulanacak ve onaylandıktan sonra bir sonrakine geçilecektir. Tüm kodlamalar `teqlif_architectural_decisions.md` (Clean Architecture) anayasasına bağlı kalacaktır.

---

## 🌐 Faz 7: Cloudflare DNS Yapılandırması (V1.4)

V1.4 mimarisinde Edge sunucularının (LiveKit ve MinIO) istemciler (kullanıcılar) ile doğrudan iletişim kurabilmesi için (WebRTC P2P bağlantıları ve limitsiz medya aktarımı) her Edge sunucusunun kendine özel, Cloudflare Proxy'sini atlayan (DNS Only) public bir DNS adresi olmalıdır.

Aşağıdaki tabloya göre Cloudflare üzerindeki DNS (A kayıtları) güncellemelerini yapınız.

### 1. Gateway & Core (Proxied)
API ve Frontend trafiğini Gateway (Nginx proxy) karşılayıp Wireguard üzerinden Core sunucuya (Node5) aktarır.

| Kayıt Tipi | İsim | Hedef IPv4 (Gateway IP) | Proxy Durumu | Not |
| :--- | :--- | :--- | :--- | :--- |
| A | `teqlif.com` | `94.16.105.135` | ☁️ Proxied (Turuncu) | Ana domain |
| A | `api.teqlif.com` | `94.16.105.135` | ☁️ Proxied (Turuncu) | Backend API |
| A | `staging.teqlif.com` | `94.16.105.135` | ☁️ Proxied (Turuncu) | Staging |

### 2. Edge 1 - Node1 (DNS Only)
LiveKit WebRTC UDP trafiği ve yüksek boyutlu MinIO veri akışı için Cloudflare proxy'si (Turuncu bulut) **KESİNLİKLE KAPALI** (Gri bulut) olmalıdır.

| Kayıt Tipi | İsim | Hedef IPv4 (Node1 IP) | Proxy Durumu | Not |
| :--- | :--- | :--- | :--- | :--- |
| A | `live1.teqlif.com` | `135.125.175.223` | ☁️ DNS Only (Gri) | Edge 1 LiveKit adresi |
| A | `minio1.teqlif.com` | `135.125.175.223` | ☁️ DNS Only (Gri) | Edge 1 MinIO adresi |

### 3. Edge 2 - Node4 (DNS Only)
Yeni kurulan Node4 Edge sunucusu.

| Kayıt Tipi | İsim | Hedef IPv4 (Node4 IP) | Proxy Durumu | Not |
| :--- | :--- | :--- | :--- | :--- |
| A | `live2.teqlif.com` | `51.75.74.124` | ☁️ DNS Only (Gri) | Edge 2 LiveKit adresi |
| A | `minio2.teqlif.com` | `51.75.74.124` | ☁️ DNS Only (Gri) | Edge 2 MinIO adresi |

> [!WARNING]  
> **Silinecek / Değişecek Eski Kayıtlar:**
> V1.3'ten kalan `live.teqlif.com`, `live-staging.teqlif.com`, `uploads.teqlif.com`, `uploads-staging.teqlif.com` ve `minio.teqlif.com` kayıtları karmaşayı önlemek için Cloudflare'dan **SİLİNMELİDİR**. 
> V1.4 Orchestrator'u artık istemcilere tek bir adres değil, dinamik olarak `live1`, `live2`, `minio1`, `minio2` gibi Edge spesifik adresler verecektir.

---

## 🔒 Faz 8: SSL (Sertifika) Yönetimi ve Temizliği

V1.4 dağıtık (Multi-Edge) mimarisinde SSL sertifika yönetimi node'ların rollerine göre bölünmüştür. Cloudflare'ın Proxied (Turuncu bulut) avantajı sadece Gateway'de kullanılacağı için Edge node'lar (Gri bulut) kendi Let's Encrypt sertifikalarını barındırmak zorundadır.

### 1. SSL Temizliği (Node1)
Eski V1.3 Monolitik yapısında **Node1**, `api.teqlif.com` ve `teqlif.com` sertifikalarını üzerinde tutuyordu. V1.4'te API trafiği Node5'e, SSL sonlandırması ise Gateway'e taşındığı için Node1 üzerindeki eski sertifikalar geçersizdir ve **temizlenmelidir**.
- **Otomasyon:** `node1_cleanup.sh` scripti içine `/etc/letsencrypt` dizinini tamamen silen bir adım eklenmiştir.

### 2. Yeni SSL İstemleri (Provisioning)

| Node | Domainler | Yönetim | Otomasyon Scripti |
| :--- | :--- | :--- | :--- |
| **Gateway** | `teqlif.com`, `api.teqlif.com` | Nginx + Certbot plugin | `gateway/resources/certbot_gateway.sh` |
| **Node1 (Edge 1)** | `live1.teqlif.com`, `minio1.teqlif.com` | Certbot Standalone | `node1/resources/certbot_node1.sh` |
| **Node4 (Edge 2)** | `live2.teqlif.com`, `minio2.teqlif.com` | Certbot Standalone | `node4/resources/certbot_node4.sh` |

> **Edge Sertifika Entegrasyonu:** Edge node'larda `certbot_node*.sh` scriptleri 80 portunu kullanarak standalone sertifika alır. Daha sonra LiveKit (Caddy) veya MinIO konfigürasyon dosyalarında bu sertifika yolları (`/etc/letsencrypt/live/.../fullchain.pem`) gösterilmelidir.
