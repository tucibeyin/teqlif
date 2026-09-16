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
- `[/]` Görev 1.2: `deploy/scale/V1.4/node4/resources` dizininin açılması. Node4 (Edge 2) için `bootstrap_node4.sh`, `node4_services.sh`, `node4_production_requirements.txt` ve `.env.production.template` dosyalarının oluşturulması. (Commit: -, Date: -)
- `[ ]` Görev 1.3: `deploy/scale/V1.4/node1/resources` dizininin açılması. Node1'in (Edge 1) yeni V1.4 rolüne uygun olarak `bootstrap_node1.sh`, `node1_services.sh`, `node1_production_requirements.txt` ve şablonlarının sıfırdan oluşturulması. (Commit: -, Date: -)
- `[ ]` Görev 1.4: Gateway, Node2 ve Node3 için V1.4 kaynak dizinlerinin açılarak Network/UFW/Wireguard trafik güncellemelerini barındıran scriptlerin baştan yazılması. **Gateway için `certbot_gateway.sh`** scriptinin de V1.4'e (Node5 upstreame) göre port edilmesi. (Commit: -, Date: -)

## 🧠 Aşama 2: Backend Refactor - Konfigürasyon ve Ajanlar
- `[ ]` Görev 2.1: `backend/app/config.py` refactor'ü. `livekit_url` ve `minio_endpoint`'in kaldırılıp dinamik `.env` listesi okuyan (Pydantic validator) yapısına dönüştürülmesi. (Commit: -, Date: -)
- `[ ]` Görev 2.2: `scripts/edge_metrics_agent.py` yazılımı. psutil ile CPU, Ağ, Disk (%80 kota takibi) verilerini toplayıp Node5'in Redis'ine 3 saniyede bir iletmesi. (Commit: -, Date: -)

## 🔀 Aşama 3: Backend Refactor - Dinamik Orkestratör ve Servisler
- `[ ]` Görev 3.1: `app/services/stream_orchestrator.py` servisinin (Clean Architecture'a uygun) kodlanması. Edge yüklerine (Redis) göre anlık LiveKit ve MinIO node'u seçimi. (Commit: -, Date: -)
- `[ ]` Görev 3.2: `storage_service.py` refactor'ü. Tekil istemci (client) yerine orkestratörden dönen node adresine MinIO yüklemesinin (Standalone Quota'ya uygun) yapılması. (Commit: -, Date: -)
- `[ ]` Görev 3.3: `stream_utils.py` ve Use-Cases (start/join/cohost) servislerinin, LiveKit URL'lerini dinamik orkestratörden alacak şekilde güncellenmesi. (Commit: -, Date: -)

## 🚀 Aşama 4: Canlı Sunucu Operasyonları (Execution & Migration)
*Not: Bu aşamada sunuculara SSH ile erişilecektir.*
- `[ ]` Görev 4.1: Node5 (Core) sunucusunda `bootstrap_node5.sh` çalıştırılması, PostgreSQL, Core Redis, limitli ClickHouse (1.5GB) servislerinin ayağa kalkması. (Commit: -, Date: -)
- `[ ]` Görev 4.2: Node1'deki (Eski) verilerin (`pg_dump`, MinIO dosyaları) Node5 ve Node4'e göçünün (Migration) sağlanması. (Commit: -, Date: -)
- `[ ]` Görev 4.3: Node4'ün (Yeni Edge) `bootstrap_node4.sh` ile tamamen formatlanarak devreye alınması (LiveKit, Local Redis, %80 Quota MinIO). (Commit: -, Date: -)
- `[ ]` Görev 4.4: Node1'in üzerindeki ağır yüklerden arındırılarak `bootstrap_node1.sh` (V1.4) ile Edge rolüne (Node4'ün ikizi) formatlanması. (Commit: -, Date: -)
- `[ ]` Görev 4.5: Gateway `nginx.conf` ayarlarının devreye alınarak API trafiğinin doğrudan Node5'e (Core) kaydırılması. (Commit: -, Date: -)
