# Teqlif Scale V1.4 - Mimari ve Orkestrasyon Kararları (Findings)

Bu belge, monolitik yapıdan Node5 (Core) ve Node1 & Node4 (Edge) yapısına geçişte alınan nihai mimari kararları ve darboğaz analizlerini özetlemektedir.

## 1. Donanım ve Rol Dağılımı

Yeni mimaride sunucular fiziksel yeteneklerine göre rollere ayrılmıştır:

*   **Node5 (Core / Orchestrator):** 
    *   **Özellikler:** ZAP-Hosting (Münster, DE), 4 Core AMD EPYC 7763, 7.8 GiB RAM.
    *   **Rol:** İşlemci performansı yüksek olduğu için FastAPI, PostgreSQL, ClickHouse ve **Ana Redis (Core)** bu makineye taşınmıştır. Sistemdeki trafiğin yöneticisi (beyni) burasıdır.

*   **Node1 & Node4 (Edge / Streaming & Storage):**
    *   **Özellikler:** OVH (Frankfurt, DE), 6 Core Intel Haswell, 11.4 GiB RAM, 2 Gbps Unmetered Ağ.
    *   **Rol:** Bant genişliği ve geniş NVMe diskleri nedeniyle saf *Streaming (LiveKit)* ve *Distributed MinIO (Depolama)* düğümleri olarak kullanılacaklardır.

## 2. Neden Mediasoup V2.0'a Ertelendi?
Teqlif'in mobil kod tabanı (teqlif/mobile) sadece canlı yayınlar için değil, **1'e 1 özel aramalar (Calls)** için de (iOS CallKit ve Android Telecom entegrasyonu dahil) tamamen LiveKit'e göbekten bağlıdır. İlk lansman (Launch) sürecinde bu kadar büyük bir mobil refactor (WebRTC ve Signaling Server yazımı) projesine girmek risklidir. Bu nedenle V1.4 için LiveKit'in maksimum verimlilikte kullanılmasına, Mediasoup mimarisinin ise V2.0 (Motor Değişimi) projesi olarak planlanmasına karar verilmiştir.

## 3. İzole Edge, Local Redis ve MinIO Media Sharding

V1.4 felsefesi "Edge sunucuların tamamen bağımsız çalışması" üzerine kuruludur. LiveKit'in hantal "Cluster Modu" ve MinIO'nun "Distributed Modu" (dosyaları bölerek WAN üzerinden eşitleme) sistemden çıkarılmıştır.

**Nihai Verimlilik ve Medya Orkestrasyonu Kararı:**
1.  **LiveKit İzolasyonu:** Node1 ve Node4 kendi içlerinde izole `redis-server` (Port 6379) çalıştırarak LiveKit'i yönetecek. Node5 çöksün veya WireGuard kopsun, Edge'lerdeki yayınlar ve aramalar KOPMAYACAKTIR.
2.  **MinIO Standalone & 80% Quota:** Node1 ve Node4'teki MinIO'lar cluster olmayacak, birbirini tanımayacak. Her biri bağımsız (Standalone) çalışacak. Diski doldurup OS'i çökertmemesi için MinIO `mc admin user quota` ile %80 (Örn: 75 GB) limite hapsedilecek.
3.  **Media & Stream Orchestrator (Node5):** Yeni yazılacak `edge_metrics_agent` 3 saniyede bir Edge'lerin Ağ, CPU ve **Disk Doluluk Oranını** Node5'e bildirecek. Biri medya (foto/video) yükleyeceğinde, Node5 diski %80'in altında olan en müsait Edge'i seçecek. Dosya **bütünlüğü bozulmadan tek parça halinde** o node'a yazılacak.

**Bu Yapının Dev Avantajları:**
*   **Sıfır Darboğaz:** Edge'ler kendi yükünü kendi donanımıyla çözer. Node5, LiveKit pub/sub işlemlerinden ve MinIO I/O işlemlerinden tamamen arındırılır.
*   **Tam Hata Toleransı ve Hız:** Bir dosya bölünmediği için okuma hızı diskin maksimum NVMe limitinde gerçekleşir. SPOF (Tek Nokta Hatası) yoktur.

## 4. Operasyonel Değişim Matrisi (V1.3 -> V1.4)

| Node | Donanım (YABS) | V1.3 Rolü & Yükleri (Mevcut) | V1.4 Rolü & Yükleri (Yeni) | Teknik Operasyon (Görevler) |
| :--- | :--- | :--- | :--- | :--- |
| **Node1** | OVH (DE)<br>11.4 GB RAM<br>6 Core | **Monolithic Prod (SPOF)**<br>`teqlif` (FastAPI), `arq-worker`<br>`postgresql`, `clickhouse`<br>`redis-server` (Tüm Poollar)<br>`livekit`, `minio` | **Edge 1 (Saf Medya & Storage)**<br>`livekit` (İzole - WebRTC :7880)<br>`redis-server` (Sadece LiveKit için)<br>`minio` (Standalone İzole :9010)<br>`edge-metrics-agent` | 1. `teqlif`, `arq`, `postgresql`, `clickhouse` durdurulup Node5'e taşınacak.<br>2. Redis pool'ları (app, cache, pubsub) iptal edilecek.<br>3. MinIO İzole Standalone moda alınacak (%80 Quota). |
| **Node4** | OVH (DE)<br>11.4 GB RAM<br>6 Core | *(Sistemde Yok)* | **Edge 2 (Saf Medya & Storage)**<br>`livekit` (İzole - WebRTC :7880)<br>`redis-server` (Sadece LiveKit için)<br>`minio` (Standalone İzole :9010)<br>`edge-metrics-agent` | 1. Node4 WireGuard (10.10.0.x) ağına eklenecek.<br>2. Node1'in birebir ikizi olarak Edge medyası (SFU) kurulacak.<br>3. MinIO Standalone kurulacak (%80 Quota). |
| **Node5** | ZAP-Hosting<br>7.8 GB RAM<br>4 Core EPYC | *(Sistemde Yok)* | **Core 1 (Backend & DB Master)**<br>`teqlif` (FastAPI Orchestrator)<br>`teqlif-worker` (ARQ Default & Critical)<br>`postgresql` (Master)<br>`clickhouse` (1.5GB RAM Limitli)<br>`redis-server` (Core PubSub/Cache) | 1. WireGuard Mesh'e katılacak.<br>2. **Sıfırdan kurulum** — veri taşıması yapılmaz, sistem yeni kayıtlarla başlar.<br>3. Sadece Core görevler yapacak (Monitor/Log almayacak). |
| **Gateway** | Netcup<br>1.9 GB RAM<br>2 Core | **Trafik & L7 Güvenlik**<br>`nginx` (:443 SSL Termination)<br>Cloudflare IP Allowlist<br>Rate Limiter (1800/dk) | **Trafik Yönlendirici (Gateway)**<br>`nginx` (Gateway)<br>`fail2ban` | 1. Nginx `proxy_pass` upstream IP'si Node5'e çevrilecek.<br>2. Sadece ters vekil (Gateway) görevini sürdürecek. Monitor servisleri Node3'te kalacak. |
| **Node3** | ZAP-Hosting<br>3.8 GB RAM<br>4 Core EPYC | **Staging, AI & Monitor**<br>`teqlif-staging`, `minio-staging`<br>`teqlif-ai-proxy` (İkincil)<br>`prometheus`, `loki`, `grafana` | **Monitor, Staging & AI Proxy**<br>`prometheus`, `loki`, `grafana`<br>`alertmanager`<br>`teqlif-staging`, `minio-staging`<br>`teqlif-ai-proxy` (İkincil) | **Değişiklik Yok:** Tüm sistemi bu node üzerinden gözlemleyeceğiz (Monitoring yığını burada kalacak). Gateway ve Node5 bu yükten muaf tutulacak. |
| **Node2** | RackNerd<br>1.4 GB RAM<br>1 Core | **AI & Failover (ABD IP)**<br>`teqlif-ai-proxy` (Birincil)<br>`cf-failover` daemon | **AI & Failover**<br>`teqlif-ai-proxy` (Birincil)<br>`cf-failover` daemon | **Değişiklik Yok:** Groq/Gemini bypass zincirinde ilk durak ve DNS A kaydı bekçisi olmaya devam edecek. |

## 5. "Sıfır Statik Veri" (No Hardcoding) Prensibi

Sistemdeki hiçbir operasyonel parametre (Kota limitleri, saniye aralıkları, IP adresleri, eşikler) kod içerisine gömülü (hardcoded) olmayacaktır. Mimari tamamen konfigürasyon güdümlü (Configuration-Driven) tasarlanmıştır.

*   **MinIO Quota Config:** MinIO'nun o node üzerinde kullanabileceği maksimum disk yüzdesi kod içinde %80 olarak sabitlenmeyecektir. `.env` dosyasına (Örn: `MINIO_STORAGE_QUOTA_PERCENT=80`) konulacak ve yönetim scriptleri/ajanlar bu sınırı oradan dinamik olarak okuyacaktır.
*   **Edge Metrics Agent:** Metrik gönderme aralığı koda gömülü "3 saniye" olmayacak, `.env` içerisinden (Örn: `EDGE_METRICS_INTERVAL_SEC=3`) okunacaktır.
*   **Tam Esneklik:** Bu sayede ileride Node4'e daha büyük bir disk takıldığında koda dokunmadan sadece `.env` güncellenerek MinIO kotası anında değiştirilebilecektir. Tüm V1.4 altyapısı (ClickHouse RAM limitleri dahil) bu `resources/` altındaki `.env` dosyalarından beslenecektir.

## 6. Otomasyon ve Idempotent Kurulum Standartları (Bootstrap)

Teqlif altyapısının kurulumunda kullanılan `bootstrap_*.sh` dosyalarının analizine dayanarak, V1.4 geçişinde ve yeni Node (Node4/Node5) kurulumlarında mevcut endüstri standardı otomasyon felsefesi korunacaktır:

1.  **Idempotency (Tekrarlanabilirlik):** Tüm bash scriptleri defalarca çalıştırılabilecek (idempotent) şekilde tasarlanmıştır. Paketler, ufw kuralları, `.env` şablonları veya systemd servisleri zaten kuruluysa atlanır veya üzerine güvenle yazılır. Hata durumunda scripti tekrar çalıştırmak güvenlidir.
2.  **OS ve Kernel Tuning (IaC):** Sunucu performansını etkileyen tüm sysctl ağ optimizasyonları, I/O udev zamanlayıcıları (scheduler), UFW Cloudflare IP havuzu kısıtlamaları ve SSH Hardening (Şifre girişinin kapatılması, Auth limitleri) işlemleri manuel değil, scriptler tarafından otomatik olarak `/etc` altına işlenir.
3.  **Dinamik Servis Enjeksiyonu:** `node_exporter`, `promtail` gibi binary dosyalar, işletim sisteminin paket yöneticisi beklenmeden doğrudan ilgili sürümleriyle indirilip `/usr/local/bin`'e yerleştirilir. 
4.  **Global Çevre Değişkenleri:** Uygulamanın kullandığı gizli veriler `TEQLIF_ENV_FILE` mantığıyla `/etc/environment` üzerine PAM modülü üzerinden global olarak işlenir. Böylece cron job'lardan `systemd` servislerine kadar her süreç `.env.production` dosyasını merkez alarak çalışır.

V1.4 altyapısında da Node4 (Edge) ve Node5 (Core) kurulumları için aynı kalitede `bootstrap_node4.sh` ve `bootstrap_node5.sh` dosyaları üretilecek ve manuel müdahale minimuma (sadece WireGuard anahtar üretimi ve `.env` şifre dolumu) indirilecektir.

## 7. Yazılım Felsefesi: Clean Architecture & Clean Code

Teqlif mimarisinde yazılacak her yeni kod, refactor edilecek her servis ve eklenecek her otomasyon scripti **kesin ve tavizsiz** olarak aşağıdaki prensiplere uymak zorundadır:

1.  **Clean Architecture (Temiz Mimari):** 
    *   İş mantığı (Business Logic / Use Cases) ile altyapı (Infrastructure / DB, Redis, MinIO) kesin çizgilerle birbirinden ayrılmalıdır. 
    *   Veritabanı veya 3. parti kütüphane değişimleri (Örn: LiveKit'ten Mediasoup'a geçiş) Core iş mantığını etkilememelidir.
2.  **Clean Code (Temiz Kod):**
    *   **SOLID & DRY:** Sınıflar ve fonksiyonlar tek bir sorumluluğa (Single Responsibility) sahip olmalı, kod tekrarından (DRY - Don't Repeat Yourself) kaçınılmalıdır.
    *   **İsimlendirme:** Değişken, fonksiyon ve dosya isimleri, ne iş yaptıklarını yorum satırına ihtiyaç bırakmayacak kadar net anlatmalıdır.
    *   **Side-Effect Koruması:** Gizli yan etkiler barındıran (beklenmeyen durumları tetikleyen) fonksiyonlardan kaçınılmalıdır.
3.  **Mecburi Kurallar:** Bu belgedeki mimari kararlar (`teqlif_architectural_decisions.md`) tüm geliştirme süreçlerinin anayasasıdır. Hiçbir kod bloğu bu kararları, "Sıfır Statik Veri" prensibini ve Clean Architecture felsefesini ezemez.

## 8. Mevcut Kod Tabanı (V1.3) ve Refactor Hedefleri

`backend/app/config.py` ve `app/use_cases/streams/` dizinlerindeki mevcut kod tabanı analiz edildiğinde, sistemin şu anda tek bir monolitik node (V1.3) varsayımıyla çalıştığı tespit edilmiştir:
*   Mevcut kodda `settings.livekit_url` ve `settings.minio_endpoint` tekil string değerleridir. Oysa V1.4 mimarisi birden fazla bağımsız Edge node'unu (Node1 ve Node4) gerektirir.

**Kritik Refactor Kuralları (V1.4):**
1.  **`.env` Şablonlarına Mutlak Sadakat:** Node5'in (ve diğer tüm node'ların) `.env` şablonları (`deploy/scale/resources/{node}/.env.*.template`) tek "Source of Truth" (Doğruluk Kaynağı) olmaya devam edecektir. Edge sunucularının adresleri bu şablonlara virgülle ayrılmış listeler olarak (Örn: `EDGE_LIVEKIT_URLS="https://live1.teqlif.com,https://live2.teqlif.com"`) eklenecektir. Not: URL formatı `https://` olarak saklanır; LiveKit istemci SDK'sı `https://` URL'i alarak WebSocket bağlantısını kendi içinde `wss://` olarak kurar.
2.  **`config.py` Refactor'ü:** FastAPI'nin çevre değişkenlerini okuyan `config.py` dosyası refactor edilecektir. `config.py` hiçbir statik/hardcoded orkestrasyon kararı vermeyecek, yalnızca `.env` dosyasındaki virgüllü listeleri okuyup Python List formatına çeviren **güvenli bir köprü (parser)** görevi görecektir.
3.  **Dinamik Edge Orkestratörü:** İstemcilere dönülen LiveKit ve MinIO URL'leri, doğrudan `config.py` üzerinden (statik olarak) alınmayacaktır. Araya girecek olan "Stream/Media Orchestrator" servisi; `config.py`'nin `.env`'den okuduğu node havuzuna bakacak, ardından Redis'teki `edge_metrics_agent` (CPU/Disk) verilerini sorgulayarak o an için en müsait olan (Örn: diski %80'in altında olan) node'u seçip istemciye sunacaktır.
