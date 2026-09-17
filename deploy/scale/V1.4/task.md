# Teqlif Scale V1.4 - Execution Tasks (task.md)

**Kurallar (Her Görev İçin Mecburidir):**
1. **Mimari Sadakat:** Tüm adımlar `teqlif_architectural_decisions.md`, Clean Architecture ve Clean Code (SOLID/DRY) prensiplerine harfiyen uyacaktır.
2. **Kullanıcı İncelemesi (Review):** Kodlama veya otomasyon betikleri yazıldığında kullanıcı ile "Review" aşamasına geçilecek, manuel girilmesi gereken şifre/config detayları açıkça kullanıcıya bildirilecektir.
3. **Test Senaryosu (Test Case):** Her adımın doğrulama senaryosu (test adımları) `V1.4/test.md` dosyasına yazılacak ve kullanıcıdan test edilmesi / onaylanması istenecektir.
4. **Onay ve İşaretleme:** Kullanıcı test onayı verdiğinde görev `[x]` ile işaretlenecek ve tamamlandığı Tarih ile Commit Numarası görevin yanına eklenecektir.
5. **Git Push:** Görev başarıyla onaylandıktan sonra değişiklikler uzak sunucuya (Git) push edilecektir.

---

## 🛠️ Aşama 1: Altyapı Şablonları (Clean State & Full Resources Rewrite)
*Not: Bu aşamada her node için sadece `bootstrap_*.sh` değil; eski V1.3 `resources` yapısındaki tüm spesifik dosyalar (`*_services.sh`, `*_requirements.txt`, tuning scriptleri, certbot vb.) sıfırdan V1.4'e göre yazılacaktır.*
- `[x]` Görev 1.0: `deploy/scale/V1.4/README.md` oluşturulması. Yeni sunucular (Node4, Node5) için manuel yapılması gereken "0. Yeni VPS — Ortak İlk Hazırlık" (Kullanıcı oluşturma, SSH, Repo Clone, MOTD vb.) adımlarının V1.4'e göre belgelenmesi. (Commit: 12e4afad, Date: 2026-09-16)
- `[x]` Görev 1.1: `deploy/scale/V1.4/node5/resources` dizininin açılması. Node5 (Core) için `bootstrap_node5.sh`, `node5_services.sh`, `node5_production_requirements.txt`, `.env.production.template` ile birlikte **`apply_pg_tuning.sh`** ve yeni **`apply_ch_tuning.sh`** (2.0GB RAM Deli Gömleği) dosyalarının sıfırdan oluşturulması. (Commit: 6643f126, Date: 2026-09-16)
- `[x]` Görev 1.2: `deploy/scale/V1.4/node4/resources` dizininin açılması. Node4 (Edge 2) için `bootstrap_node4.sh`, `node4_services.sh`, `node4_production_requirements.txt` ve `.env.production.template` dosyalarının oluşturulması. (Commit: df3b06ff, Date: 2026-09-16)
- `[x]` Görev 1.3: `deploy/scale/V1.4/node1/resources` dizininin açılması. Node1'in (Edge 1) yeni V1.4 rolüne uygun olarak `bootstrap_node1.sh`, `node1_services.sh`, `node1_production_requirements.txt` ve şablonlarının sıfırdan oluşturulması. (Commit: c49ea325, Date: 2026-09-16)
- `[x]` Görev 1.4: Gateway, Node2 (AI Proxy 1) ve Node3 (Staging/Monitor/AI Proxy 2) için V1.4 kaynak dizinlerinin açılarak Network/UFW/Wireguard trafik güncellemelerini barındıran scriptlerin baştan yazılması. **Gateway için `certbot_gateway.sh`** scriptinin de V1.4'e (Node5 upstreame) göre port edilmesi. (Commit: 8827ba8b, Date: 2026-09-16)
- `[x]` Görev 1.5: Cloudflare DNS Yapılandırmasının Belgelenmesi. `plan.md` (Faz 7) içerisine, V1.4 Orchestrator mimarisinde Edge node'ların doğrudan public hizmet verebilmesi için gerekli olan DNS tablolarının (Proxied/DNS Only kuralları) işlenmesi. (Commit: 26cf95b9, Date: 2026-09-16)
- `[x]` Görev 1.6: V1.4 mimarisine özel 6-Node (Core ve Edge 2 dahil) WireGuard ağ topolojisinin Node bağımsız `resources/wg0.conf` dosyaları olarak oluşturulması. (Commit: pending, Date: 2026-09-16)

## 🧠 Aşama 2: Backend Refactor - Konfigürasyon ve Ajanlar
- `[x]` Görev 2.1: `backend/app/config.py` refactor'ü. `livekit_url` ve `minio_endpoint`'in kaldırılıp dinamik `.env` listesi okuyan (Pydantic validator) yapısına dönüştürülmesi. (Commit: f198cbe5, Date: 2026-09-16)
- `[x]` Görev 2.2: `scripts/edge_metrics_agent.py` ajanının yazılması (CPU, RAM, Disk, Net istatistiklerinin Core Redis'e yazılması). (Commit: f198cbe5, Date: 2026-09-16)
- `[x]` Görev 2.3: `app/services/edge_orchestrator.py` sınıfının yaratılması ve `allocate_node(service_type)` jenerik kaynak yöneticisi mantığının kodlanması. (Tamamen soyutlanmış yapı). (Commit: 4d5af235, Date: 2026-09-16)
- `[x]` Görev 2.4: **(ClickHouse Optimizasyonu)** Backend API ve modellerindeki `user_id` ve `listing_id` alanlarının `String`'den `int` (UInt32) tipine çevrilmesi ve `Nullable` türlerin iptal edilmesi. (Commit: d694afba, Date: 2026-09-16)
- `[x]` Görev 2.5: **(ClickHouse Optimizasyonu)** FastAPI background worker'larının `FLUSH_INTERVAL` değerinin 30 saniyeye, `MAX_BATCH` limitinin 5000'e çıkarılması. Şema yaratma scriptlerine `ZSTD(3)`, Bloom Filter ve kısa TTL sürelerinin eklenmesi. (Commit: d694afba, Date: 2026-09-16)

## 🔀 Aşama 3: Backend Refactor - Dinamik Orkestratör ve Servisler
- `[x]` Görev 3.1: `edge_orchestrator.py` servisinin (Clean Architecture ve Strategy pattern'a uygun) kodlanması. İhtiyaca göre (CPU vs Disk) jenerik Edge Node tahsisi yapılması. (Commit: 4d5af235, Date: 2026-09-16)
- `[x]` Görev 3.2: `storage_service.py` refactor'ü. Tüm Edge node'lar için bir "MinIO Connection Pool" oluşturulması. Kayıt (Upload) esnasında Orkestratör'den node atanması; Silme (Delete) esnasında ise veritabanındaki URL'in parse edilip doğru node'a silme isteğinin yönlendirilmesi (Media Routing). (Commit: 5920a27e, Date: 2026-09-16)
- `[x]` Görev 3.3: `stream_utils.py` (Yayınlar) ve `calls.py` (VoIP) servislerinin, LiveKit URL'lerini dinamik orkestratörden alacak şekilde güncellenmesi. (Commit: 163d04a6, Date: 2026-09-16)

## 🚀 Aşama 4: Canlı Sunucu Operasyonları (Execution & Migration)
*Not: Bu aşamada sunuculara SSH ile erişilecektir.*

### 🏗️ Faz 5: Node5 (Core) Deployment & Bootstrap
- `[x]` Node5 sunucu hazırlığı ve V1.4 standartlarına uygun klasör hiyerarşisi oluşturulması. (Commit: 12e4afad)
- `[x]` `bootstrap_node5.sh` scriptinin revize edilerek sıfır kurulum (Clean State) için uygun hale getirilmesi. (Commit: 78f19a44)
- `[x]` Veritabanı "hayalet tablo" (Modeli olmayan tablolar) sorunlarının çözülmesi (`Subcategory`, `Country`, `Translation`). (Commit: 65e973af)
- `[x]` systemd servis (`teqlif.service`) hatalarının (TEQLIF_ENV_FILE yolu, OOMScoreAdjust) düzeltilmesi. (Commit: 78f19a44)
- `[x]` LiveKit API anahtarlarının eksik olduğu durumlarda çökmenin engellenmesi. (Commit: 72cd6c91)
- `[x]` `teqlif` servisinin `Active (running)` durumuna getirilmesi ve Node5 entegrasyonunun tamamlanması. (Commit: 72cd6c91, Date: 2026-09-17)

- `[x]` Görev 4.2: Node1'deki (Eski) verilerin (`pg_dump`, MinIO dosyaları) göçünün **İPTAL EDİLMESİ** — Sistem sıfırdan kurulum (No Migration) kuralıyla baştan kurulacak. (Commit: -, Date: 2026-09-17)
- `[x]` Görev 4.3: Node4'ün (Yeni Edge) `bootstrap_node4.sh` ile tamamen formatlanarak devreye alınması (LiveKit, Local Redis, %80 Quota MinIO, edge-metrics-agent). (Commit: 2026fa30)
- `[x]` Görev 4.4: Node1'in üzerindeki ağır yüklerden arındırılarak `bootstrap_node1.sh` (V1.4) ile Edge rolüne (Node4'ün ikizi) formatlanması.
- `[x]` Görev 4.5: Gateway `teqlif.com.conf` ayarlarının güncellenmesi: `teqlif.com` isteklerinin Gateway üzerinden `/var/www/teqlif.com/frontend` dizininden statik sunulması, `api.teqlif.com` isteklerinin ise Node5'e (FastAPI) proxy edilmesi (Decoupling). (Commit: f0dbf30, Date: 2026-09-17)
## 📡 Aşama 5: Ağ Birleştirme ve İzleme Dağıtımı (Gateway & AI Proxies)
- `[x]` Görev 5.1: Gateway'in `bootstrap_gateway.sh` ile V1.4 (Saf Ters Vekil) formatına formatlanması ve WireGuard key'inin üretilmesi.
- `[x]` Görev 5.2: Node2'nin (AI Proxy 1) `bootstrap_node2.sh` ile V1.4 formatına getirilmesi ve WireGuard key'inin üretilmesi.
- `[x]` Görev 5.3: Node3'ün (AI Proxy 2 & Staging & Monitoring) `bootstrap_node3.sh` ile V1.4 formatına getirilmesi ve WireGuard key'inin üretilmesi.
- `[x]` Görev 5.4: Üretilen tüm WireGuard Public Key'lerin `deploy/scale/V1.4/*/resources/wg0.conf` şablonlarında güncellenmesi ve ağın "Full-Mesh" (Herkes birbirini görür) olarak tüm sunucularda ayağa kaldırılması (Senkronizasyon).

## 🌍 Aşama 6: DNS ve SSL Sertifikasyonu
- `[ ]` Görev 6.1: Cloudflare DNS A kayıtlarının `plan.md` "Faz 7" tablosuna uygun olarak Gateway (Proxied) ve Edge sunucular (DNS Only) için güncellenmesi.
- `[x]` Görev 6.2: Gateway'de `certbot_gateway.sh` çalıştırılarak wildcard/Nginx sertifikalarının alınması.
- `[ ]` Görev 6.3: Node1 ve Node4'te `certbot_nodeX.sh` çalıştırılarak Edge (LiveKit ve MinIO) sertifikalarının alınması.

## 🏁 Aşama 7: Son Başlatma ve Final Testleri
- `[ ]` Görev 7.1: Node1 ve Node4 (Edge'ler) üzerinde MinIO ve LiveKit servislerinin SSL yollarıyla birlikte aktifleştirilmesi.
- `[ ]` Görev 7.2: Node2 ve Node3 üzerinde AI Proxy servislerinin başlatılması.
- `[ ]` Görev 7.3: Mobil istemci (Uygulama) üzerinden "Yayın Başlatma" ve "Dosya Yükleme" (MinIO) işlemlerinin uçtan uca test edilmesi.
