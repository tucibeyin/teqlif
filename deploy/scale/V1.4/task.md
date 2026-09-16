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
- `[x]` Görev 1.4: Gateway, Node2 ve Node3 için V1.4 kaynak dizinlerinin açılarak Network/UFW/Wireguard trafik güncellemelerini barındıran scriptlerin baştan yazılması. **Gateway için `certbot_gateway.sh`** scriptinin de V1.4'e (Node5 upstreame) göre port edilmesi. (Commit: 8827ba8b, Date: 2026-09-16)
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
- `[ ]` Görev 4.1: Node5 (Core) sunucusunda `bootstrap_node5.sh` çalıştırılması, PostgreSQL, Core Redis, limitli ClickHouse (1.5GB) servislerinin ayağa kalkması. (Commit: -, Date: -)
- `[ ]` Görev 4.2: Node1'deki (Eski) verilerin (`pg_dump`, MinIO dosyaları) Node5 ve Node4'e göçünün (Migration) sağlanması. (Commit: -, Date: -)
- `[ ]` Görev 4.3: Node4'ün (Yeni Edge) `bootstrap_node4.sh` ile tamamen formatlanarak devreye alınması (LiveKit, Local Redis, %80 Quota MinIO). (Commit: -, Date: -)
- `[ ]` Görev 4.4: Node1'in üzerindeki ağır yüklerden arındırılarak `bootstrap_node1.sh` (V1.4) ile Edge rolüne (Node4'ün ikizi) formatlanması. (Commit: -, Date: -)
- `[ ]` Görev 4.5: Gateway `nginx.conf` ayarlarının devreye alınarak API trafiğinin doğrudan Node5'e (Core) kaydırılması. (Commit: -, Date: -)
