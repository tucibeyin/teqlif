# Teqlif Scale V1.3 — Kapsamlı Mimari ve Uygulama Belgesi

> **Uygulama tarihi:** 2026-09-11 / 2026-09-12  
> **Durum:** Aktif (production)  
> **Önceki sürüm:** `deploy/scale/V1.2/`  
> **Kaynak dosyalar:** `deploy/scale/V1.3/`, `deploy/scale/resources/`

---

## 1. Genel Bakış

Scale V1.3, V1.2 üzerine tek büyük mimari genişlemedir: **node3 (Ashburn VA)** 4 rolde eklenir.

| Rol | V1.2 | V1.3 |
|---|---|---|
| AI Proxy (ikincil) | — | ✅ node3 |
| Monitoring stack (Prometheus/Loki/Alertmanager) | gateway | node3 |
| Staging ortamı | node1 | node3 |
| Off-site backup hedefi | — | node3 |

Motivasyon:
1. **Gateway yük azaltma:** Monitoring stack gateway'den kaldırılarak onun 2 GB RAM'i boşaltılır.
2. **Staging izolasyonu:** Staging, production node1'den bağımsız node3'e taşınır.
3. **AI Proxy dayanıklılığı:** node2'nin tek proxy olmasından kaynaklanan SPOF giderilir.
4. **Off-site backup:** Türkiye/Avrupa dışı coğrafi yedek (ABD Ashburn).

### V1.3 ile gelen değişiklikler

| # | Değişiklik | Etki |
|---|---|---|
| 1 | node3 (Zap-Hosting Ashburn VA) eklendi | 4 yeni rol — AI proxy ikincil, monitoring, staging, backup hedefi |
| 2 | Monitoring stack gateway → node3 | gateway RAM boşaltıldı; gateway artık prometheus/loki/alertmanager çalıştırmıyor |
| 3 | Staging node1 → node3 | teqlif-staging, teqlif-worker-staging node3'te; node1 tamamen prod |
| 4 | `generate_via_node2` → `generate_via_proxy` | node2 birincil, node3 ikincil, node1 son fallback |
| 5 | `node2_internal_token` → `ai_proxy_internal_token` | Naming temizliği; 3 node aynı token |
| 6 | `LOG_NODE` env var — `logging_config.py` | `{LOG_NODE}-app.log` / `error.log` — Loki'de node etiketiyle ayırt |
| 7 | Systemd `Wants=` + `PartOf=` + `BindsTo=` | `systemctl restart teqlif` → worker'lar da restart olur |
| 8 | `TEQLIF_ENV_FILE` tüm servislere eklendi | Servis doğru env dosyasını okur; symlink/path hatası ortadan kalkar |
| 9 | `ExecStartPre` — alembic + sync_main | Restart = deploy; DB migration + çeviri sync otomatik |
| 10 | `teqlif-backup.service` + `.timer` (node1) | Her gece 03:00 UTC — pg_dump lokal + rsync → node3 |
| 11 | Off-site rsync (node1 → node3 WireGuard) | `/root/.ssh/id_backup` ED25519 key, 14 gün Redis retention |
| 12 | WireGuard 3-node → 4-node mesh | node3 diğer 3 node'a tam peer |
| 13 | Loki'ye push adresi: gateway:3100 → node3:3100 | node1, node2, gateway promtail'leri node3'e yönlendirildi |
| 14 | promtail positions: `/tmp` → `/var/lib/promtail/` | root sahiplik sorunu giderildi; reboot sonrası kayıp önlendi |
| 15 | pydantic Settings `extra='ignore'` | `.env`'de bilinmeyen alan varsa ValidationError yerine sessizce atlanır |
| 16 | MinIO: node3'te staging bucket'ları | `teqlif-staging`, `teqlif-dm-staging` — node1'den kaldırıldı |
| 17 | LiveKit staging — node3 | `live-staging.teqlif.com` — ayrı key/secret, staging SFU |
| 18 | node1 staging temizliği | teqlif_staging DB, Redis db=1, MinIO bucket'ları, UFW 8001 silindi |
| 19 | node2 `.env.cfFailover` kaldırıldı | CF vars `.env.production`'a taşındı; role-based env isimlendirmesi |
| 20 | Env dosyaları role-based isimlendirmeye geçti | `.env.node1.production` → `.env.production` (her node kendi dizininde) |
| 21 | Bootstrap scriptleri V1.3'e güncellendi | Tüm node'lar: rsync, `/var/lib/promtail/`, backup dizini, curl←wget |
| 22 | Redis bind: `127.0.0.1 + 10.10.0.1` (node1) | `0.0.0.0` yerine lokal + WireGuard — UFW'ya ek derinlikte savunma |
| 23 | bootstrap_node3.sh: log dizini + mc alias | `/var/log/teqlif` oluşturma; `mc alias set node3-staging` + bucket otomasyonu |

---

## 2. Donanım

### node1 — OVHcloud Frankfurt (Ana Backend)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **OVHcloud SAS** (FR) |
| Lokasyon | Frankfurt, Almanya |
| Public IP | 135.125.175.223 |
| WireGuard IP | 10.10.0.1 |
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 2 GiB Swap |
| Disk | 98.3 GiB NVMe |
| Ağ | **2 Gbps fixed / Unlimited** |
| SSH alias | `teqlif-node1` |

### gateway — netcup GmbH Nürnberg (Edge Proxy)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **netcup GmbH** (DE) |
| Lokasyon | Nürnberg, Almanya |
| Public IP | 94.16.105.135 |
| WireGuard IP | 10.10.0.2 |
| CPU | 2 vCore (QEMU @ 2.29 GHz) |
| RAM | 2 GB + 1 GB Swap |
| Disk | 60 GB SSD |
| Ağ | **1 Gbps fixed / Unlimited — 24h ort. >100 Mbps → geçici throttle; ort. düşünce otomatik kalkar** |
| SSH alias | `teqlif-gateway` |
| V1.3 notu | Prometheus/Loki/Alertmanager kaldırıldı — node_exporter + promtail + nginx kalır |

### node2 — VPSHostingService.co Buffalo (AI Proxy Birincil)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **VPSHostingService.co** (US) |
| Lokasyon | Buffalo, New York, ABD |
| Public IP | 198.12.123.33 |
| WireGuard IP | 10.10.0.3 |
| CPU | 1 vCore |
| RAM | 1 GB |
| Disk | 25 GB SSD |
| Ağ | **1 Gbps shared / Unlimited** |
| SSH alias | `teqlif-node2` |
| Hostname | `node2` |

### node3 — Zap-Hosting Ashburn VA (AI Proxy İkincil + Monitoring + Staging + Backup) ← **V1.3'te eklendi**

| Parametre | Değer |
|---|---|
| Sağlayıcı | **Zap-Hosting GmbH** (DE) |
| Lokasyon | Ashburn, Virginia, ABD |
| Public IP | 5.249.165.10 |
| WireGuard IP | 10.10.0.4 |
| CPU | 2 vCore |
| RAM | 3.2 GiB + 4 GiB Swap |
| Disk | 50 GB SSD |
| Ağ | **1 Gbps fixed / Unlimited — 33 TB/ay @ 1 Gbps, sonrası 10 Mbps throttle** |
| SSH alias | `teqlif-node3` |
| Hostname | `node3` |
| Aylık ücret | $81.66 |
| Panel notu | **90 günde bir giriş zorunlu** — sonraki: **~2026-12-10** |

---

## 3. Topoloji ve Trafik Akışı

```
                    ┌─────────────────────────────────────────────┐
 İnternet           │           CLOUDFLARE EDGE                   │
                    │  (DDoS koruma, SSL proxy, CDN cache)        │
                    └──────────────┬──────────────────────────────┘
                                   │ HTTPS
                    ┌──────────────▼──────────────────────────────┐
                    │     gateway (netcup GmbH, 94.16.105.135)     │
                    │                                              │
                    │  nginx (SSL termination, rate limit,         │
                    │         microcaching)                        │
                    │  WireGuard (10.10.0.2)                       │
                    │  node_exporter :9100  ← node3 scrape         │
                    │  promtail → node3:3100                       │
                    └──────┬───────────────────────┬──────────────┘
                           │ WireGuard             │ WireGuard
              ┌────────────▼────────────┐  ┌───────▼──────────────────────────────┐
              │  node1 (OVHcloud, FR)   │  │  node3 (Zap-Hosting, Ashburn VA)     │
              │                         │  │                      ← V1.3           │
              │  FastAPI prod   :8000    │  │  FastAPI staging    :8001             │
              │  PostgreSQL     :5432    │  │  ARQ workers (staging)                │
              │  Redis          :6379    │  │  AI Proxy (secondary) :8080           │
              │  MinIO          :9010    │◄─┤  MinIO staging      :9010             │
              │  ClickHouse     :8123    │  │  PostgreSQL staging :5432             │
              │  LiveKit SFU    :7880+   │  │  Redis staging      :6379             │
              │  ARQ Workers             │  │  LiveKit staging    :7880+            │
              │  WireGuard (10.10.0.1)  │  │  Prometheus  :9090                    │
              │  node_exporter  :9100    │  │  Loki        :3100  ← tüm node push  │
              │  promtail → 10.10.0.4   │  │  Alertmanager :9093                   │
              │  teqlif-backup.timer    │  │  node_exporter :9100                  │
              └─────────────────────────┘  │  promtail (kendi logları)             │
                                           │  WireGuard (10.10.0.4)                │
                                           └──────────────────────────────────────┘
              ┌──────────────────────────────────────┐
              │  node2 (VPSHostingService.co, US)    │
              │  AI Proxy (primary)  :8080            │
              │  cf-failover daemon                   │
              │  node_exporter  :9100                 │
              │  promtail → 10.10.0.4                 │
              │  WireGuard (10.10.0.3)                │
              └──────────────────────────────────────┘
```

### AI Açıklama Üretim Akışı (V1.3)

```
Mobil → POST /api/listings/generate-description
  └─ node1: listings.py → generate_via_proxy(params)
       └─ node2_ai_proxy_url doluysa:
            POST http://10.10.0.3:8080/generate  (45s timeout)
              X-Internal-Token: AI_PROXY_INTERNAL_TOKEN
            └─ node2: ai_proxy_main.py → Groq + Gemini (ABD IP)
       └─ node2 down / timeout → node3 ikincil proxy:
            POST http://10.10.0.4:8080/generate  (30s timeout)
            └─ node3: ai_proxy_main.py → Groq + Gemini (ABD IP)
       └─ node3 down / timeout → lokal Groq fallback (node1 EU IP)
```

### Fallback Zinciri

```
node2 (Groq + Gemini, ABD IP — birincil)
    ↓  down / timeout
node3 (Groq + Gemini, ABD IP — ikincil)  ← V1.3
    ↓  down / timeout
node1 (Groq only — EU IP, Gemini çalışmaz — son fallback)
    ↓  tüm Groq modelleri exhausted
AIServiceBusyException (503)
```

---

## 4. Servis Dağılımı

| Servis | node1 | gateway | node2 | node3 | Gerekçe |
|---|---|---|---|---|---|
| FastAPI prod (:8000) | ✅ | ❌ | ❌ | ❌ | PostgreSQL/Redis yakınlığı |
| FastAPI staging (:8001) | ❌ → ✅ | ❌ | ❌ | ✅ | **V1.3: node1'den node3'e taşındı** |
| PostgreSQL (prod) | ✅ | ❌ | ❌ | ❌ | Disk I/O + worker erişimi |
| PostgreSQL (staging) | ❌ → ✅ | ❌ | ❌ | ✅ | **V1.3: node3'te ayrı DB** |
| Redis (prod) | ✅ | ❌ | ❌ | ❌ | node2/node3 WireGuard üzerinden |
| Redis (staging) | ❌ → ✅ | ❌ | ❌ | ✅ | **V1.3: node3 lokal Redis** |
| MinIO (prod) | ✅ | ❌ | ❌ | ❌ | OVHcloud unmetered bant |
| MinIO (staging) | ❌ → ✅ | ❌ | ❌ | ✅ | **V1.3: teqlif-staging + dm-staging** |
| ClickHouse | ✅ | ❌ | ❌ | ❌ | RAM yoğun |
| LiveKit SFU (prod) | ✅ | ❌ | ❌ | ❌ | UDP medya + unmetered |
| LiveKit SFU (staging) | — | ❌ | ❌ | ✅ | **V1.3: live-staging.teqlif.com** |
| ARQ Worker (prod, genel) | ✅ | ❌ | ❌ | ❌ | ML + DB erişimi |
| ARQ Worker (prod, critical) | ✅ | ❌ | ❌ | ❌ | Bulkhead pattern |
| ARQ Worker (staging) | ❌ → ✅ | ❌ | ❌ | ✅ | **V1.3: node3'te** |
| AI Proxy (:8080) birincil | ❌ | ❌ | ✅ | ❌ | Gemini ABD IP — V1.2 |
| AI Proxy (:8080) ikincil | — | ❌ | ❌ | ✅ | **V1.3: SPOF giderildi** |
| nginx (public SSL) | ❌ | ✅ | ❌ | ❌ | Edge proxy rolü |
| nginx (fallback, port 443) | ✅ | ❌ | ❌ | ❌ | CF failover |
| nginx (uploads) | ✅ | ❌ | ❌ | ❌ | uploads.teqlif.com → MinIO |
| nginx (uploads-staging) | — | ❌ | ❌ | ✅ | **V1.3: uploads-staging.teqlif.com** |
| Prometheus | ❌ | ✅ → ❌ | ❌ | ✅ | **V1.3: gateway → node3** |
| Alertmanager | ❌ | ✅ → ❌ | ❌ | ✅ | **V1.3: gateway → node3** |
| Loki | ❌ | ✅ → ❌ | ❌ | ✅ | **V1.3: gateway → node3** |
| promtail | ✅ | ✅ | ✅ | ✅ | Her node — node3 Loki'ye push |
| node_exporter | ✅ | ✅ | ✅ | ✅ | Her node |
| cf-failover daemon | ❌ | ❌ | ✅ | ❌ | Gateway DNS failover |
| teqlif-backup.service + .timer | ✅ | ❌ | ❌ | ❌ | **V1.3: pg+rsync 03:00 UTC** |
| WireGuard | ✅ 10.10.0.1 | ✅ 10.10.0.2 | ✅ 10.10.0.3 | ✅ 10.10.0.4 | **V1.3: 4-node mesh** |

---

## 5. WireGuard 4-Node Mesh (V1.3)

```
node1   10.10.0.1  135.125.175.223:51820  ListenPort: 51820
gateway 10.10.0.2  94.16.105.135:51820    ListenPort: 51820
node2   10.10.0.3  198.12.123.33:51820    ListenPort: 51820
node3   10.10.0.4  5.249.165.10:51820     ListenPort: 51820
```

Her node diğer üçüne de peer tanımlar. PersistentKeepalive: 25s (tüm bağlantılar).

**Konfigürasyon dosyaları:**
- `deploy/scale/V1.3/wireguard/` — şablonlar (private key hariç, git'e girmez)
- Her node'da `/etc/wireguard/wg0.conf` — gerçek config (sunucularda)

**WireGuard public key'leri:**
| Node | Public Key |
|---|---|
| node1 | `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=` |
| gateway | `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=` |
| node2 | `t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k=` |
| node3 | deploy sırasında üretildi — `/etc/wireguard/node3_public.key` |

---

## 6. Systemd Servis Mimarisi (V1.3)

### Worker Bağımlılık Deseni

V1.3'te tüm ana servisler + worker çiftlerine üçlü bağımlılık uygulandı:

**Ana servis `[Unit]`:**
```ini
Wants=teqlif-worker.service teqlif-worker-critical.service
```

**Her worker `[Unit]`:**
```ini
BindsTo=teqlif.service
PartOf=teqlif.service
```

| Direktif | Etki |
|---|---|
| `Wants=` | Ana servis başlarken worker'ları da başlatır |
| `PartOf=` | Ana servis restart/stop olunca worker'lar da restart/stop olur |
| `BindsTo=` | Ana servis beklenmedik şekilde durursa worker'lar da durur |

Sonuç: `systemctl restart teqlif` → alembic migration + sync_main + 3 servis yeniden başlar.

### ExecStartPre Zinciri (prod + staging)

Her restart = deploy:
```ini
ExecStartPre=/var/www/teqlif.com/venv/bin/python -m alembic upgrade head
ExecStartPre=/var/www/teqlif.com/venv/bin/python /var/www/teqlif.com/backend/scripts/sync_main.py
```

### node1 Servis Dosyaları — `deploy/scale/V1.3/node1/systemd/`

| Dosya | Port | Workers | Notlar |
|---|---|---|---|
| `teqlif.service` | 8000 | 4 | `Wants=worker+critical`, ExecStartPre alembic+sync |
| `teqlif-worker.service` | — | 1 | `BindsTo/PartOf=teqlif.service` |
| `teqlif-worker-critical.service` | — | 1 | `BindsTo/PartOf=teqlif.service` |
| `teqlif-backup.service` | — | — | one-shot: pg-backup.sh + offsite-rsync.sh |
| `teqlif-backup.timer` | — | — | `OnCalendar=*-*-* 03:00:00` UTC |
| `node_exporter.service` | 9100 (wg0) | — | `--web.listen-address=10.10.0.1:9100` |
| `promtail.service` | — | — | push → `10.10.0.4:3100` |
| `redis-backup.service` + `.timer` | — | — | Redis RDB yedek |
| `livekit.service` | 7880/7881/7882 | — | |
| `minio.service` | 9010 | — | |

### node2 Servis Dosyaları — `deploy/scale/V1.3/node2/systemd/`

| Dosya | Port | Notlar |
|---|---|---|
| `teqlif-ai-proxy.service` | 8080 (wg0) | MemoryMax=768M |
| `cf-failover.service` | — | DNS failover daemon |
| `node_exporter.service` | 9100 (wg0) | |
| `promtail.service` | — | push → `10.10.0.4:3100` |

### node3 Servis Dosyaları — `deploy/scale/V1.3/node3/systemd/`

| Dosya | Port | Workers | Notlar |
|---|---|---|---|
| `teqlif-staging.service` | 8001 | 2 | `Wants=worker-staging+critical-staging`, ExecStartPre alembic+sync |
| `teqlif-worker-staging.service` | — | 1 | `BindsTo/PartOf=teqlif-staging.service` |
| `teqlif-worker-critical-staging.service` | — | 1 | `BindsTo/PartOf=teqlif-staging.service` |
| `teqlif-ai-proxy.service` | 8080 (wg0) | — | node3 ikincil AI proxy |
| `prometheus.service` | 9090 (localhost) | — | |
| `loki.service` | 3100 | — | tüm node'ların log hedefi |
| `alertmanager.service` | 9093 (localhost) | — | Telegram |
| `node_exporter.service` | 9100 (wg0) | — | |
| `promtail.service` | — | — | kendi loglarını lokal Loki'ye |
| `minio.service` | 9010 (staging) | — | teqlif-staging + dm-staging |
| `livekit.service` | 7880/7881/7882 | — | live-staging.teqlif.com |
| `nginx.service` | 80/443 | — | uploads-staging.teqlif.com |

### gateway Servis Dosyaları — `deploy/scale/V1.3/gateway/systemd/`

| Dosya | Port | Notlar |
|---|---|---|
| `node_exporter.service` | 9100 (wg0) | `--web.listen-address=10.10.0.2:9100` — node3 scrape |
| `promtail.service` | — | push → `10.10.0.4:3100` |

**V1.3'te kaldırılanlar:** `prometheus.service`, `loki.service`, `alertmanager.service`

### LiveKit Mimarisi

LiveKit **pure SFU** (Selective Forwarding Unit) modunda çalışır — transcoding yok, sadece RTP paket yönlendirme.

| Parametre | Değer |
|---|---|
| Mod | **SFU** — transcoding yok, CPU yükü minimaI |
| Sinyal (WebSocket) | `wss://teqlif.com/rtc` → Cloudflare → gateway → node1 |
| Medya (UDP/RTP) | **Doğrudan node1** `135.125.175.223:50000-60000` — gateway bypass |
| Yayıncı bant genişliği | ~1–2 Mbps upload (720p) |
| İzleyici bant genişliği | ~1 Mbps/kişi download (node1'dan) |
| node1 medya kapasitesi | ~2.000 eşzamanlı izleyici (2 Gbps / 1 Mbps) |
| Her açık artırma | 1 LiveStream odası = 1 yayıncı + N abone |

Yapılandırma: `deploy/scale/V1.3/node1/livekit.yaml` — `node_ip: 135.125.175.223`, `use_external_ip: false`, TURN etkin.

---

## 7. Off-site Backup (V1.3)

### Mimari

```
node1 (03:00 UTC)
  └─ teqlif-backup.timer → teqlif-backup.service
       ├─ ExecStart: /usr/local/sbin/pg-backup.sh
       │     └─ pg_dump teqlif | gzip → /var/backups/pg/teqlif-YYYY-MM-DD.sql.gz
       │        (lokal 3 gün retention)
       └─ ExecStart: /usr/local/sbin/offsite-rsync.sh
             └─ rsync -az /var/backups/ → tucibeyin@10.10.0.4:/var/backups/teqlif/
                (WireGuard + /root/.ssh/id_backup ED25519)
                (node3'te Redis: 14 gün retention)
```

### SSH Key (node1 → node3)

```bash
# node1'de üretim:
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_backup -N "" -C "node1-backup"
# node3'te authorized:
~/.ssh/authorized_keys  # node1 public key eklendi
```

### Backup Dizinleri

| Node | Dizin | İçerik | Retention |
|---|---|---|---|
| node1 | `/var/backups/pg/` | `teqlif-YYYY-MM-DD.sql.gz` | 3 gün (lokal) |
| node3 | `/var/backups/teqlif/pg/` | pg_dump rsync kopyası | rsync ile node1 ile senkron |
| node3 | `/var/backups/teqlif/redis/` | Redis RDB rsync kopyası | 14 gün |

---

## 8. Monitoring Stack (node3)

### Bileşenler

| Bileşen | Versiyon | Konum | V1.3 Değişikliği |
|---|---|---|---|
| prometheus | 2.51.0 | node3 | gateway'den taşındı; 4-node scrape |
| alertmanager | 0.27.0 | node3 | gateway'den taşındı; Telegram v2 API |
| loki | 3.6.7 | node3 | gateway'den taşındı; tüm node'lardan push |
| promtail | 3.0.0 | her 4 node | push URL → node3:3100; positions → `/var/lib/promtail/` |
| node_exporter | 1.8.2 | her 4 node | gateway: WireGuard IP'de dinliyor |

### Prometheus Scrape Hedefleri

```yaml
- job_name: 'node-gateway'   targets: ['10.10.0.2:9100']
- job_name: 'node-node1'     targets: ['10.10.0.1:9100']
- job_name: 'node-node2'     targets: ['10.10.0.3:9100']
- job_name: 'node-node3'     targets: ['10.10.0.4:9100']
- job_name: 'livekit'        targets: ['10.10.0.1:7881']
- job_name: 'postgres'       targets: ['10.10.0.1:9187']
- job_name: 'prometheus'     targets: ['localhost:9090']
```

Final doğrulamada tüm hedefler UP: `livekit up / node-gateway up / node-node1 up / node-node2 up / node-node3 up / postgres up / prometheus up`

### Loki Yapılandırması

Tüm node'lar `http://10.10.0.4:3100/loki/api/v1/push` adresine push yapar. promtail `node` label ile etiketler. `curl /loki/api/v1/label/node/values` → `node1, node2, node3, gateway`.

### Alertmanager

Telegram bot ile entegre. `send_resolved: true` — DOWN ve UP bildirimleri ayrı mesaj. `group_wait: 30s`, `group_interval: 5m`. Alert API v2 (`/api/v2/alerts`) kullanılır — v1 deprecated.

---

## 9. Backend Kod Değişiklikleri (V1.3)

### `backend/app/services/ml/ai_proxy_client.py`

```python
async def generate_via_proxy(params) -> tuple[str, str]:
    # 1. node2 dene (birincil, 45s timeout)
    if settings.node2_ai_proxy_url:
        try:
            r = await _client.post(f"{node2_ai_proxy_url}/generate", timeout=45)
            return r.json()["text"], r.json()["provider"]
        except Exception:
            logger.warning("[AI-PROXY] node2 başarısız, node3'e geçiyor")
    # 2. node3 dene (ikincil, 30s timeout)
    if settings.node3_ai_proxy_url:
        try:
            r = await _client.post(f"{node3_ai_proxy_url}/generate", timeout=30)
            return r.json()["text"], r.json()["provider"]
        except Exception:
            logger.warning("[AI-PROXY] node3 başarısız, lokal fallback")
    # 3. node1 lokal Groq fallback
    return await generate_listing_description(**params)
```

### `backend/app/config.py`

```python
node2_ai_proxy_url: str = ""    # V1.2'den: node2 birincil proxy
node3_ai_proxy_url: str = ""    # V1.3: node3 ikincil proxy
ai_proxy_internal_token: str = ""  # V1.3: node2_internal_token yerine
```

`Settings.Config.extra = "ignore"` — V1.3'te eklendi. `.env` dosyasında tanımsız alan varsa ValidationError yerine sessizce atlanır.

### `backend/app/logging_config.py`

```python
LOG_NODE = os.environ.get("LOG_NODE", "node1")
# Log dosya adları: {LOG_NODE}-app.log, {LOG_NODE}-error.log, {LOG_NODE}-worker.log
```

Loki'de `node` label değeri bu değerden gelir. Her servis kendi `Environment=LOG_NODE=...` satırını tanımlar.

---

## 10. Deploy Konfigürasyonu — `deploy/scale/resources/` (V1.3)

```
deploy/scale/resources/
├── node1/
│   ├── .env.production                        # prod env şablonu — V1.3: LOG_NODE=node1 eklendi
│   ├── node1_production_requirements.txt
│   ├── bootstrap_node1.sh                     # V1.3: rsync, /var/lib/promtail/, redis-backup.sh kopyası, Redis bind kısıtlaması
│   ├── node1_services.sh                      # teqlif-staging kaldırıldı
│   └── apply_pg_tuning.sh
├── node2/
│   ├── .env.production                        # V1.3: .env.cfFailover birleştirildi
│   ├── node2_production_requirements.txt
│   ├── bootstrap_node2.sh
│   └── node2_services.sh
├── node3/                                     # V1.3: yeni dizin
│   ├── .env.production                        # AI proxy env (GROQ, GEMINI, TOKEN)
│   ├── .env.staging                           # Staging env (DB, Redis, MinIO, LiveKit, vb.)
│   ├── node3_staging_requirements.txt         # production + staging paketleri
│   ├── bootstrap_node3.sh
│   └── node3_services.sh
└── gateway/
    ├── .env.gateway.production                # TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
    ├── bootstrap_gateway.sh                   # V1.3: monitoring binary'leri kaldırıldı
    ├── gateway_services.sh                    # prometheus/loki/alertmanager kaldırıldı
    └── certbot_gateway.sh
```

### Env Dosyası Değişiklikleri (V1.3)

| V1.2 | V1.3 | Değişiklik |
|---|---|---|
| `resources/node1/.env.node1.production` | `resources/node1/.env.production` | Role-based isimlendirme |
| `resources/node1/.env.node1.staging` | **silindi** | Staging node3'e taşındı |
| `resources/node2/.env.node2.production` | `resources/node2/.env.production` | CF vars eklendi |
| `resources/node2/.env.node2.cfFailover` | **silindi** | `.env.production`'a birleştirildi |
| — | `resources/node3/.env.production` | AI proxy env (yeni) |
| — | `resources/node3/.env.staging` | Staging env (yeni) |

### Systemd EnvironmentFile Path'leri (V1.3)

| Servis | Node | EnvironmentFile |
|---|---|---|
| `teqlif.service` | node1 | `.../resources/node1/.env.production` |
| `teqlif-worker.service` | node1 | `.../resources/node1/.env.production` |
| `teqlif-worker-critical.service` | node1 | `.../resources/node1/.env.production` |
| `teqlif-staging.service` | node3 | `.../resources/node3/.env.staging` |
| `teqlif-worker-staging.service` | node3 | `.../resources/node3/.env.staging` |
| `teqlif-worker-critical-staging.service` | node3 | `.../resources/node3/.env.staging` |
| `teqlif-ai-proxy.service` | node2 | `.../resources/node2/.env.production` |
| `teqlif-ai-proxy.service` | node3 | `.../resources/node3/.env.production` |
| `cf-failover.service` | node2 | `.../resources/node2/.env.production` |
| `alertmanager.service` | node3 | `/etc/alertmanager/alertmanager.yml` (envsubst ile render) |

---

## 11. Firewall (UFW)

### node1

```
22/tcp          ALLOW   Anywhere          # SSH
443/tcp         ALLOW   Cloudflare IPs    # HTTPS — CF failover fallback
51820/udp       ALLOW   Anywhere          # WireGuard
8000/tcp on wg0 ALLOW   10.10.0.2         # API prod — gateway
9100/tcp on wg0 ALLOW   10.10.0.4         # node_exporter — node3 Prometheus  ← V1.3
9187/tcp on wg0 ALLOW   10.10.0.4         # postgres_exporter — node3  ← V1.3
7881/tcp on wg0 ALLOW   10.10.0.4         # LiveKit metrics — node3  ← V1.3
6379/tcp on wg0 ALLOW   10.10.0.3         # Redis — node2
6379/tcp on wg0 ALLOW   10.10.0.4         # Redis — node3 AI proxy  ← V1.3
```

**V1.3'te kaldırılanlar:** `8001/tcp on wg0 ALLOW 10.10.0.2` (staging node3'e taşındı)

### node2

```
22/tcp          ALLOW   Anywhere          # SSH
51820/udp       ALLOW   Anywhere          # WireGuard
8080/tcp on wg0 ALLOW   Anywhere (wg0)    # AI proxy — mesh
9100/tcp on wg0 ALLOW   Anywhere (wg0)    # node_exporter — Prometheus
```

### node3 (V1.3 — yeni)

```
22/tcp          ALLOW   Anywhere          # SSH
80/tcp          ALLOW   Anywhere          # HTTP — uploads-staging
443/tcp         ALLOW   Anywhere          # HTTPS — uploads-staging
51820/udp       ALLOW   Anywhere          # WireGuard
8001/tcp on wg0 ALLOW   10.10.0.2         # staging FastAPI — gateway
8080/tcp on wg0 ALLOW   Anywhere (wg0)    # AI proxy — mesh
3100/tcp on wg0 ALLOW   Anywhere (wg0)    # Loki — tüm node push
9100/tcp on wg0 ALLOW   Anywhere (wg0)    # node_exporter — Prometheus self
7880/tcp        ALLOW   Anywhere          # LiveKit API/WebSocket staging
7882/tcp        ALLOW   Anywhere          # LiveKit RTC/TCP staging
7882/udp        ALLOW   Anywhere          # LiveKit RTC/UDP staging
3478/udp        ALLOW   Anywhere          # LiveKit TURN/UDP staging
5349/tcp        ALLOW   Anywhere          # LiveKit TURN/TLS staging
50000:60000/udp ALLOW   Anywhere          # LiveKit media port range staging
```

### gateway

```
22/tcp          ALLOW   Anywhere          # SSH
80/tcp          ALLOW   Anywhere          # HTTP
443/tcp         ALLOW   Anywhere          # HTTPS
51820/udp       ALLOW   Anywhere          # WireGuard
9100/tcp on wg0 ALLOW   10.10.0.4         # node_exporter — node3 Prometheus  ← V1.3
```

**V1.3'te kaldırılanlar:** `3100/tcp on wg0 ALLOW 10.10.0.1` ve `3100/tcp on wg0 ALLOW 10.10.0.3` (Loki node3'e taşındı)

---

## 12. journald Limitleri (V1.3)

Tüm node'larda Loki 14 günlük log saklar; journald kısa vadeli yerel yedek rolüne indirildi.

| Node | SystemMaxUse | SystemKeepFree | MaxRetentionSec |
|---|---|---|---|
| node1 | 200M | 2G | **2d** (V1.2: 500M/1week) |
| gateway | 100M | 1G | **2d** (V1.2: 300M/1week) |
| node2 | 100M | 200M | **2d** (V1.2: 200M/1week) |
| node3 | 200M | — | 2d (yeni) |

---

## 13. Deploy Workflow (V1.3)

### Rutin Deploy (kod değişikliği)

```bash
# Yerel
git push

# node1 veya node3 — tek komut yeterli
# git pull + alembic + sync_main + restart + canlı izleme hepsini yapar
sudo teqlif-restart

# node2
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy

# node3 — ai proxy (sadece ai proxy güncelleniyorsa)
sudo systemctl restart teqlif-ai-proxy
```

> `teqlif-restart` kurulumu (VPS'te bir kez): `sudo install -m 755 deploy/scale/V1.3/scripts/teqlif-restart.sh /usr/local/bin/teqlif-restart`

### Manuel Backup Çalıştırma

```bash
# node1'de:
sudo systemctl start teqlif-backup.service
sudo journalctl -u teqlif-backup.service -n 30
# node3'te doğrulama:
ls -lh /var/backups/teqlif/pg/
```

### Monitoring Güncelleme (V1.3'te node3'te)

```bash
# node3'te:
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.3/node3/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp deploy/scale/V1.3/node3/prometheus-rules.yml /etc/prometheus/rules/teqlif.yml
sudo systemctl restart prometheus
```

### node3 Staging .env Güncelleme

```bash
# node3'te:
nano /var/www/teqlif.com/deploy/scale/resources/node3/.env.staging
sudo systemctl restart teqlif-staging
```

### Yeni Node Kurulumu

```bash
# 1. Repo klonla
git clone <repo-url> /var/www/teqlif.com
cd /var/www/teqlif.com

# 2. WireGuard key üret (sır — git'e girmez)
sudo bash -c 'wg genkey | tee /etc/wireguard/<node>_private.key | wg pubkey > /etc/wireguard/<node>_public.key'

# 3. Bootstrap çalıştır
bash deploy/scale/resources/<node>/bootstrap_<node>.sh

# 4. .env değerlerini doldur
nano deploy/scale/resources/<node>/.env.production

# 5. Servisleri başlat
bash deploy/scale/resources/<node>/<node>_services.sh start
```

---

## 14. Rollback Planı (V1.3)

| Senaryo | Aksiyon |
|---|---|
| node2 AI proxy çöker | node3 ikincil proxy otomatik devreye girer — 30s timeout |
| node3 AI proxy çöker | node1 lokal Groq fallback — Gemini yok, servis devam eder |
| node3 monitoring çöker | Prometheus/Loki/Alertmanager down — gateway'de binary'ler hâlâ mevcut: `sudo systemctl start prometheus loki alertmanager` (gateway'de) ile geçici geri dönüş |
| node3 staging çöker | staging.teqlif.com → 502 — production etkilenmez |
| Backup başarısız | `sudo systemctl start teqlif-backup.service` ile manuel çalıştır; node3 erişilemezse rsync "node3 erişilemiyor" uyarısı ile atlanır, lokal pg_dump korunur |
| gateway çöker | **Otomatik:** node2 cf-failover daemon 30s içinde CF DNS A → node1 |
| WireGuard bozulur | `sudo systemctl restart wg-quick@wg0` |
| V1.2'ye dönüş | node1'e teqlif-staging.service geri kur; gateway'de prometheus/loki/alertmanager başlat; node3 izole et |

---

## 15. V1.3 Uygulama Sırasında Karşılaşılan Sorunlar

### 1. pydantic ValidationError — boş env değerleri

**Sorun:** `teqlif.service` yeni `EnvironmentFile` yolunu (`resources/node1/.env.production`) okurken `db_pool_size`, `captcha_enabled` gibi sayısal/bool alanlarda boş string değeri `ValidationError` üretiyordu. Eski `backend/.env` dolu, şablon dosyası boştu.

**Çözüm:** `cp backend/.env resources/node1/.env.production` ile gerçek değerler kopyalandı. Ek olarak `Settings.Config.extra = 'ignore'` eklendi.

### 2. StartLimitBurst — kalıcı failed durumu

**Sorun:** pydantic hatası nedeniyle servis 10 kez crash etti, `StartLimitBurst=10` limitine ulaştı. `systemctl restart` artık çalışmıyordu.

**Çözüm:** `sudo systemctl reset-failed teqlif` → ardından restart.

**Kural:** Servis sürekli restart deniyor ama başlamıyorsa ilk kontrol: `systemctl is-failed <servis>`. `failed` dönüyorsa `reset-failed` yap.

### 3. Worker'lar restart sonrası inactive kaldı

**Sorun:** `PartOf=` tek başına stop/restart'ı yayar ama **start'ı yaymaz**. `systemctl restart teqlif` sonrası worker'lar inactive kaldı.

**Çözüm:** `teqlif.service [Unit]`'e `Wants=teqlif-worker.service teqlif-worker-critical.service` eklendi.

### 4. rsync bulunamadı — backup başarısız

**Sorun:** `offsite-rsync.sh` node3'te `rsync: command not found` hatası verdi — uzak tarafta da rsync gerekiyor.

**Çözüm:** `sudo apt install -y rsync` node3'te kuruldu. `bootstrap_node3.sh`'a eklendi.

### 5. /var/backups/teqlif permission denied

**Sorun:** Dizin yoktu — rsync hedefi oluşturulamadı.

**Çözüm:** `sudo mkdir -p /var/backups/teqlif/{pg,redis} && sudo chown -R tucibeyin:tucibeyin /var/backups/teqlif`. Bootstrap'e eklendi.

### 6. node-node1 Prometheus'ta DOWN

**Sorun:** node1'de node3 için port 9100 UFW kuralı eklenmemişti.

**Çözüm:** `sudo ufw allow in on wg0 from 10.10.0.4 to any port 9100 proto tcp`. `bootstrap_node1.sh`'a eklendi.

### 7. node2 git pull merge conflict

**Sorun:** node2'de lokal `.env.node2.production` ve `.env.node2.cfFailover` gerçek değerleri vardı; V1.3'te bu dosyalar yeniden adlandırıldı. `git stash -u && git pull && git stash pop` sonrası merge conflict kaldı.

**Çözüm:** `git checkout --theirs deploy/scale/resources/node2/.env.production` (yeni şablonu al) + `git rm .env.node2.cfFailover` + stash drop. Ardından `AI_PROXY_INTERNAL_TOKEN` node1'den kopyalandı.

### 8. promtail /tmp/positions.yaml permission denied

**Sorun:** Önceki bir çalışmada root olarak oluşturulan `/tmp/positions.yaml`, `tucibeyin` kullanıcısı olarak çalışan promtail tarafından açılamıyordu.

**Çözüm:** Tüm node'larda positions path `/tmp/positions.yaml` → `/var/lib/promtail/positions.yaml` olarak değiştirildi. Bootstrap'lara `sudo mkdir -p /var/lib/promtail && sudo chown tucibeyin:tucibeyin /var/lib/promtail` eklendi.

### 9. MinIO GitHub releases URL bozuk

**Sorun:** `dl.min.io` URL'i 410 Gone döndürüyor. bootstrap'te `wget -q` sessizce 0-byte binary indirdi.

**Çözüm:** `github.com/minio/minio/releases/download/RELEASE.YYYY-.../minio.linux-amd64.RELEASE.YYYY-...` doğru asset adı kullanıldı. `curl -fsSL` ile değiştirildi.

### 10. Alertmanager v1 API deprecated

**Sorun:** `/api/v1/alerts` ile test alert gönderildi — `{"status":"deprecated","error":"...removed as of version 0.28.0"}`.

**Çözüm:** `/api/v2/alerts` kullanıldı.

### 11. node3 UFW lockout — VNC recovery

**Sorun:** `sudo ufw --force enable` WireGuard kuralları eklenmeden çalıştırıldı → SSH bağlantısı kesildi.

**Çözüm:** Zap-Hosting panel VNC console ile root girişi. Klavye layout farklıydı (Shift+7=`?` yerine `/` çıkmıyor); `ufw allow 22` komutu ve slash'siz alternatifler kullanıldı.

**Kural:** UFW enable öncesi `ufw status numbered` ile SSH kuralının var olduğunu doğrula.

### 12. node3_services.sh promtail mkdir eksikti

**Sorun:** `start/restart` sırasında `/var/lib/promtail/` dizini gateway ve node2_services.sh'da oluşturuluyordu ama node3_services.sh'da yoktu. promtail `positions.yaml` yazamıyor, crash loop.

**Çözüm:** `node3_services.sh start|restart` bloğuna `sudo mkdir -p /var/lib/promtail && sudo chown tucibeyin:tucibeyin /var/lib/promtail` eklendi.

### 13. redis-backup.sh /usr/local/sbin/'a kopyalanmıyordu

**Sorun:** `bootstrap_node1.sh` redis-backup.service ve .timer dosyalarını kopyalıyordu ama `redis-backup.sh` script'ini `/usr/local/sbin/`'a kopyalamıyordu. Servis `ExecStart=/usr/local/sbin/redis-backup.sh` hatasıyla başarısız oluyordu.

**Çözüm:** Bootstrap'e `sudo cp "$REPO/deploy/scripts/redis-backup.sh" /usr/local/sbin/redis-backup.sh && sudo chmod +x` eklendi.

### 14. MinIO mc alias adı "node3-staging" — test "local" varsayıyordu

**Sorun:** `mc alias list` JSON parse'ı SSH BatchMode'da başarısız olunca test `mc_alias="local"` fallback yapıyordu. Gerçek alias adı `node3-staging` (port 9010).

**Çözüm:** Test `mc alias list --json` çıktısını `9010` içeren satır için filtreliyor; fallback `"node3-staging"` olarak güncellendi. `bootstrap_node3.sh`'a `.env.staging` doluysa otomatik `mc alias set node3-staging` + bucket oluşturma eklendi.

### 15. LiveKit API secret staging/production uyumsuzluğu

**Sorun:** `/etc/livekit/livekit.yaml`'daki `api_secret` ile `.env.staging` içindeki `LIVEKIT_API_SECRET` farklıydı. Token doğrulama hatası.

**Çözüm:** `sudo sed -i "s|api_secret:.*|api_secret: $secret|"` ile `livekit.yaml` güncellendi; `sudo systemctl restart livekit`.

**Kural:** Bootstrap `livekit.yaml`'ı sadece dosya yoksa kopyalar. `.env.staging` dolduktan sonra secret'ı elle güncellemek gerekiyor.

### 16. Redis bind sed uygulanmadı — /etc/redis/redis.conf'ta bind satırı yoktu

**Sorun:** `sed -i 's/^bind .*/...'` eşleşmiyordu çünkü bazı Redis kurulumlarında `redis.conf`'ta `bind` satırı comment'lı veya hiç yok.

**Çözüm:** `bootstrap_node1.sh`'a `grep -qE '^bind '` kontrolü eklendi; satır varsa sed, yoksa `tee -a` ile ekleniyor.

### 17. ss çıktısında 0.0.0.0:* — test yanlış alarm veriyordu

**Sorun:** `ss -tlnp | grep :6379` çıktısında "peer" kolonu `0.0.0.0:*` içeriyordu. Test `grep -qE "0\.0\.0\.0"` ile eşleşiyor, Redis `0.0.0.0`'da bind görünüyordu. Oysa local bind `127.0.0.1:6379` ve `10.10.0.1:6379`.

**Çözüm:** Pattern `0\.0\.0\.0` → `0\.0\.0\.0:6379` — port numarasıyla eşleştirince peer kolonu artık eşleşmiyor.

### 18. database.py — `Depends` import eksikti (NameError — alembic çöktü)

**Sorun:** `backend/app/database.py`'de `get_uow()` fonksiyonu `Depends(get_db)` kullanıyordu ama `from fastapi import Depends` satırı yoktu. Alembic `env.py` → `database.py` import zincirinde modül yüklenirken `NameError: name 'Depends' is not defined` hatası alındı. Servis `ExecStartPre` (alembic aşaması) anında başarısız oluyordu.

**Çözüm:** `from fastapi import Depends` satırı `database.py`'nin başına eklendi. Commit: `3742feda`.

**Kural:** Alembic `NameError`'ı migration hatasından önce gelirse suçlu `env.py` → `database.py` import zinciridir — migration dosyalarına bakma.

### 19. rate_limit.py — `coredis` yok, uvicorn worker'ları crash loop'a girdi

**Sorun:** `Limiter(storage_uri="async+redis://...")` `limits` kütüphanesi aracılığıyla `coredis >= 3.4.0` gerektiriyor. `coredis` venv'de kurulu değildi. `ConfigurationError` fırlatıldı. Systemd servisi `active` görünüyordu (uvicorn parent ayakta) ama tüm worker process'leri crash loop'a girdiğinden uygulama hiç istek almıyordu.

**Çözüm:** `storage_uri="async+" + _REDIS_URL` → `storage_uri=_REDIS_URL`. Rate limit check için sync Redis yeterli. Commit: `690f5acd`.

**Kural:** `systemctl is-active` `active` döndürse de uvicorn multi-process modunda worker'lar ölmüş olabilir. Gerçek sağlık: `journalctl -u teqlif -n 50 | grep "SpawnProcess"` veya `curl -s http://localhost:8000/health`.

### 20. node2 cf-failover — yüklü servis dosyası repoyla uyuşmuyor

**Sorun:** `/etc/systemd/system/cf-failover.service`'in yüklü versiyonu `EnvironmentFile=.../resources/node2/.env.node2.cfFailover` gösteriyordu. V1.3'te bu dosya `.env.production`'a birleştirildi ve `.env.node2.cfFailover` silindi. Servis restart sonrası env dosyasını bulamadı; daha önce hiç restart gerektirmediği için sorun gizli kalmıştı.

**Çözüm:** `sudo cp .../V1.3/node2/systemd/cf-failover.service /etc/systemd/system/` + `daemon-reload`. `.env.production`'a `CF_ZONE_ID=` ve `CF_API_TOKEN=` satırları eklendi.

**Kural:** Major versiyon geçişlerinde yüklü servis dosyalarını `systemctl cat <servis> | grep EnvironmentFile` ile repodaki şablonla karşılaştır.

### 21. gateway — git remote SSH, `sudo -u tucibeyin git pull` başarısız

**Sorun:** gateway'de git remote `git@github.com` (SSH) iken, `teqlif-restart.sh` içindeki `sudo -u tucibeyin git pull` SSH agent socket'ine (`SSH_AUTH_SOCK`) erişemedi. node1/node2/node3 HTTPS kullanıyor — sorun sadece gateway'de ortaya çıktı.

**Çözüm:** `git remote set-url origin https://github.com/tucibeyin/teqlif.git` (gateway'de bir kez uygulandı).

**Kural:** `teqlif-restart.sh` root olarak çalışır ve `sudo -u tucibeyin` ile pull atar. SSH-agent forwarding bu context'te çalışmaz; tüm node'larda HTTPS remote zorunlu.

---

## 16. Kapasite Limitleri (Kod Tabanlı)

### Gerçek Tavan Değerleri

| Katman | Değer | Kaynak |
|---|---|---|
| PostgreSQL bağlantı tavan (prod) | 4 worker × 30 = **120 app** + ~30 admin = **150 ihtiyaç** | `config.py:8-9`, `database.py:18-21` |
| PostgreSQL max_connections (varsayılan) | **100** — yetersiz, 200'e yükseltildi | `apply_pg_tuning.sh` |
| Nginx eşzamanlı WS bağlantısı | 2 worker × 4096 / 2 (upstream) = **~4.096** | `nginx.conf:9` |
| Teklif hız limiti | **1 teklif / 3 sn** per kullanıcı | `auction_commands.py:484` |
| Kullanıcı başına max WS | **8 eşzamanlı** | `defender.py:51` |
| ARQ critical queue (bildirimler) | **50 eşzamanlı iş** (30'dan artırıldı) | `worker.py:3566` |
| LiveKit max katılımcı/oda | **500** (prod) / **100** (staging) | `livekit.yaml:30` |
| API rate limit | **1.800 req/dk** + burst 200 per IP | `nginx-http-zones.conf:6` |

### Senaryo Kapasitesi

| Senaryo | Kapasite | Darboğaz |
|---|---|---|
| Pasif tarama | **~5.000 eşzamanlı** | nginx microcache 5s + PG read |
| Aktif WS bağlantısı | **~4.000 eşzamanlı** | nginx worker_connections tavan |
| Aktif teklif verici | **~800–1.500 eşzamanlı** | gateway 100 Mbps + PG write |
| Açık artırma sonu bildirimi | **~150 kullanıcıya kadar anlık**, sonrası kuyruklanır | ARQ critical 50 eşzamanlı iş |

### Uygulanan Düzeltmeler

- `apply_pg_tuning.sh`: `max_connections=200`, `shared_buffers=3GB`, `effective_cache_size=9GB`
- `apply_pg_tuning_node3.sh`: `max_connections=100`, `shared_buffers=1GB` (yeni dosya)
- `redis_client.py`: Her client'a `max_connections` sınırı eklendi (50/20/20/20)
- `worker.py`: `WorkerSettingsCritical.max_jobs` 30 → 50 (push notification I/O bound)
- `storage_service.py`: `upload_bytes_async` / `upload_file_async` wrapper'ları eklendi (MinIO sync çağrılar event loop'u kilitliyordu)
- `upload.py`: Tüm MinIO çağrıları async versiyonlara geçirildi

---

## 17. Bekleyen Görevler

- [x] **node3 Swap** — node3 artık 4 GB fiziksel RAM; bootstrap'teki 4 GB swapfile ek güvence olarak kalabilir veya kaldırılabilir.
- [x] **PostgreSQL tuning uygulaması** — `apply_pg_tuning.sh` node1'de, `apply_pg_tuning_node3.sh` node3'te uygulandı (2026-09-12)
- [ ] **Staging Sentry DSN** — `.env.staging` içinde `SENTRY_BACKEND_DSN=` boş.
- [ ] **Staging Admin Panel** — production `admin.html`'den ayrılmalı; staging URL'lerine bakmalı.
- [ ] **Staging Telegram kanalı** — alertmanager ve uygulama için ayrı bot/kanal.
- [ ] **Staging DB migration zinciri** — `alembic upgrade head` fresh DB'de kırık; `pg_dump --schema-only + alembic stamp head` geçici çözüm (V1.3'te uygulandı).
- [ ] **LiveKit cert renewal otomasyonu** — staging + prod certbot renewal cron.
- [ ] **gateway monitoring binary temizliği** — prometheus, loki, alertmanager binary'leri hâlâ `/usr/local/bin/`'de; isteğe bağlı silme.

---

## 17. V1.4 Adayları

- **Redis Sentinel / replica:** node1 Redis SPOF — yüksek erişilebilirlik için replica adayı.
- **Staging DB migration zinciri düzeltmesi:** `listings` tablosunu ALTER eden migration, tablo olmadan çalışıyor — migration kaynaklandığı commit'e kadar bölünmeli.
- **node3 panel otomasyonu:** 90 günde bir giriş gereksinimi varsa health check + reminder kurulabilir.
- **ARQ worker node2/node3'e taşıma:** AI işler zaten proxy'e yönleniyor — ARQ da taşınabilir (V2.0 adayı).

---

## 18. Commit Referansları (V1.3)

| Hash | İçerik |
|---|---|
| `8324261d` | feat(scale): V1.3 — node3 eklendi (AI proxy secondary, monitoring, staging, backup) |
| `b8151991` | feat(node3): LiveKit staging eklendi |
| `82f084e5` | refactor: env dosyaları role-based isimlendirme |
| `9c42058a` | refactor: node2 .env.cfFailover kaldırıldı |
| `433a5d40` | refactor: tüm servisler env'i doğrudan resources'tan okur |
| `2b1da11a` | fix(config): Settings extra='ignore' |
| `a3f23bbb` | feat(systemd): PartOf/BindsTo + TEQLIF_ENV_FILE |
| `e8bbcc5c` | fix(systemd): Wants= ekle — restart worker'ları da başlatır |
| `33fda83c` | fix(bootstrap): rsync + backup dizinleri node3 bootstrap'a eklendi |
| `1d29624c` | fix(bootstrap): bootstrap_node1.sh V1.3'e güncellendi |
| `406a9bea` | chore: Faz 4.4/4.5 ve Faz 5 tamamlandı |
| `706222a0` | fix(deploy): promtail positions /tmp → /var/lib/promtail; Faz 6-8 tamamlandı |
| `3742feda` | fix(database): Depends importunu ekle — alembic NameError düzeltildi |
| `690f5acd` | fix(rate_limit): coredis bağımlılığını kaldır — async+ yerine sync redis kullan |

---

## 19. Dosya Referansları

```
deploy/scale/V1.3/
├── task.md                                   # Adım adım uygulama logu — tüm fazlar [x]
├── final.md                                  # Bu belge
├── wireguard/                                # 4-node wg0.conf şablonları
├── gateway/
│   ├── promtail-config.yml                   # push → 10.10.0.4:3100
│   ├── journald/journald.conf                # SystemMaxUse=100M, MaxRetentionSec=2d
│   └── systemd/
│       ├── node_exporter.service             # --web.listen-address=10.10.0.2:9100  ← V1.3
│       └── promtail.service
├── node1/
│   ├── promtail-config.yml                   # push → 10.10.0.4:3100
│   ├── journald/journald.conf                # SystemMaxUse=200M, MaxRetentionSec=2d
│   ├── nginx/teqlif-fallback.conf            # CF failover (V1.2'den devam)
│   └── systemd/
│       ├── teqlif.service                    # Wants=worker+critical, ExecStartPre alembic+sync
│       ├── teqlif-worker.service             # BindsTo/PartOf=teqlif.service
│       ├── teqlif-worker-critical.service    # BindsTo/PartOf=teqlif.service
│       ├── teqlif-backup.service             # one-shot: pg-backup + offsite-rsync
│       ├── teqlif-backup.timer               # 03:00 UTC
│       ├── node_exporter.service
│       ├── promtail.service
│       ├── redis-backup.service + .timer
│       ├── livekit.service
│       └── minio.service
├── node2/
│   ├── promtail-config.yml                   # push → 10.10.0.4:3100
│   ├── journald/journald.conf                # SystemMaxUse=100M, MaxRetentionSec=2d
│   └── systemd/
│       ├── teqlif-ai-proxy.service           # .env.production (birleşik, cfFailover dahil)
│       ├── cf-failover.service
│       ├── node_exporter.service
│       └── promtail.service
└── node3/                                    # V1.3: yeni dizin
    ├── prometheus.yml                        # 4-node + livekit + postgres scrape
    ├── prometheus-rules.yml
    ├── alertmanager.yml.template
    ├── loki-config.yml
    ├── promtail-config.yml
    ├── livekit.yaml
    ├── journald/journald.conf                # SystemMaxUse=200M, MaxRetentionSec=2d
    ├── sysctl/99-teqlif.conf
    ├── nginx/uploads-staging.teqlif.com
    └── systemd/
        ├── teqlif-staging.service            # Wants=worker-staging, ExecStartPre alembic+sync
        ├── teqlif-worker-staging.service     # BindsTo/PartOf=teqlif-staging.service
        ├── teqlif-worker-critical-staging.service
        ├── teqlif-ai-proxy.service           # node3 ikincil AI proxy
        ├── prometheus.service
        ├── loki.service
        ├── alertmanager.service
        ├── node_exporter.service
        ├── promtail.service
        ├── minio.service
        ├── livekit.service
        └── nginx.service  (sistem paketi)

deploy/scale/resources/
├── node1/
│   ├── .env.production                       # prod env (LOG_NODE=node1, NODE3_AI_PROXY_URL)
│   ├── node1_production_requirements.txt
│   ├── bootstrap_node1.sh                    # V1.3: rsync, /var/lib/promtail/, UFW node3 kuralları
│   ├── node1_services.sh
│   └── apply_pg_tuning.sh
├── node2/
│   ├── .env.production                       # CF vars dahil (cfFailover birleşti)
│   ├── node2_production_requirements.txt
│   ├── bootstrap_node2.sh                    # V1.3: /var/lib/promtail/
│   └── node2_services.sh
├── node3/                                    # V1.3: yeni
│   ├── .env.production                       # AI proxy env
│   ├── .env.staging                          # Staging env
│   ├── node3_staging_requirements.txt
│   ├── bootstrap_node3.sh                    # rsync, /var/lib/promtail/, backup dizini, swap, /var/log/teqlif, mc alias node3-staging + bucket oluşturma
│   └── node3_services.sh
└── gateway/
    ├── .env.gateway.production               # TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
    ├── bootstrap_gateway.sh                  # V1.3: monitoring binary'leri kaldırıldı
    ├── gateway_services.sh
    └── certbot_gateway.sh

deploy/scripts/
├── pg-backup.sh                              # V1.3: pg_dump + gzip, 3 gün lokal retention
└── offsite-rsync.sh                          # V1.3: rsync → node3 WireGuard, 14 gün Redis

deploy/scale/V1.3/scripts/
└── teqlif-restart.sh                         # dispatcher — node tespiti → node-specific script'e yönlendirir

deploy/scale/V1.3/node1/scripts/
└── node1_restart.sh                          # git pull → teqlif+worker restart (canlı journal) → altyapı check → özet

deploy/scale/V1.3/node2/scripts/
└── node2_restart.sh                          # git pull → ai-proxy + cf-failover restart → özet

deploy/scale/V1.3/node3/scripts/
└── node3_restart.sh                          # git pull → teqlif-staging restart (canlı journal) → ai-proxy → altyapı+monitoring check → özet

deploy/scale/V1.3/gateway/scripts/
└── gateway_restart.sh                        # git pull → nginx -t + reload → özet

backend/app/
├── config.py                                 # ai_proxy_internal_token, node3_ai_proxy_url, extra='ignore'
├── ai_proxy_main.py                          # node2 + node3 proxy (AI_PROXY_INTERNAL_TOKEN)
├── logging_config.py                         # LOG_NODE env var, {LOG_NODE}-*.log
└── services/ml/
    └── ai_proxy_client.py                    # generate_via_proxy: node2 → node3 → node1 fallback
```

---

## 20. Performans İyileştirmeleri (V1.3)

### OS / Kernel Seviyesi

#### sysctl — `deploy/scale/V1.3/node3/sysctl/99-teqlif.conf`

node3 için uygulanan kernel parametreleri:

| Parametre | Değer | Gerekçe |
|---|---|---|
| `vm.swappiness` | `10` | RAM dolarsa önce uygulama yerine cache çıkar |
| `net.core.somaxconn` | `1024` | TCP accept backlog — nginx + uvicorn |
| `net.ipv4.tcp_max_syn_backlog` | `2048` | SYN kuyruğu — burst bağlantılar |
| `net.core.netdev_max_backlog` | `5000` | NIC → kernel kuyruk boyu |
| `vm.overcommit_memory` | `1` | ARQ worker fork sırasında OOM kill önlenir |

#### systemd Cgroup Limitleri

Servis dosyalarında cgroup direktifleri ile kaynak izolasyonu:

| Direktif | node1 `teqlif.service` | node3 `teqlif-staging.service` | Gerekçe |
|---|---|---|---|
| `CPUWeight` | `200` | `80` | Prod daha yüksek CPU önceliği |
| `IOWeight` | `200` | `200` | Disk I/O önceliği — node3'te diğer servislerle rekabet |
| `TasksMax` | `512` | `512` | Maksimum thread/process sayısı |
| `OOMScoreAdj` | `-500` | `-200` | OOM killer'a karşı koruma (prod daha agresif) |
| `LimitNOFILE` | `65536` | `65536` | Açık dosya tanımlayıcı limiti |
| `KillMode` | `mixed` | `mixed` | Ana process SIGTERM, worker'lar uyumlu kapanır |
| `TimeoutStopSec` | `30` | `30` | Graceful shutdown süresi |

ARQ worker'lar için ek ayrım:

| Direktif | `teqlif-worker` | `teqlif-worker-critical` |
|---|---|---|
| `TimeoutStopSec` | `300` (5 dk) | `600` (10 dk) |
| `KillMode` | `process` | `process` |
| Gerekçe | Uzun süreli ML/bulk işler | Push notif cascade |

### PostgreSQL Seviyesi

`apply_pg_tuning.sh` (node1) ve `apply_pg_tuning_node3.sh` (node3):

| Parametre | node1 | node3 | Varsayılan |
|---|---|---|---|
| `max_connections` | `200` | `100` | 100 |
| `shared_buffers` | `3GB` (RAM'in ~%25) | `512MB` | 128MB |
| `effective_cache_size` | `9GB` | `1.2GB` | 4GB |
| `work_mem` | `16MB` | `8MB` | 4MB |
| `maintenance_work_mem` | `512MB` | `128MB` | 64MB |
| `wal_buffers` | `64MB` | `16MB` | auto |
| `checkpoint_completion_target` | `0.9` | `0.9` | 0.5 |

#### Yeni Alembic Migration'ları: `zzzzs_perf_indexes`

7 eksik index eklendi — en yaygın sorgu yollarını kapsar:

| Index | Tablo | Kolon | Tür |
|---|---|---|---|
| `ix_favorites_listing_id` | `favorites` | `listing_id` | B-tree |
| `ix_listing_impressions_listing_id` | `listing_impressions` | `listing_id` | B-tree |
| `ix_listing_impressions_seen_at` | `listing_impressions` | `seen_at DESC` | B-tree |
| `ix_user_interests_category_score` | `user_interests` | `(category, score DESC)` | B-tree |
| `ix_direct_sale_orders_listing_id` | `direct_sale_orders` | `listing_id` | B-tree |
| `ix_listings_active_created` | `listings` | `created_at DESC` | Partial (`WHERE status='active'`) |
| `ix_listings_active_video` | `listings` | `id` | Partial (`WHERE status='active' AND video_url IS NOT NULL`) |

> **Not:** `CREATE INDEX CONCURRENTLY` Alembic transaction block içinde yasaktır. Tüm index'ler `CONCURRENTLY` olmadan oluşturulur — `ExecStartPre` sırasında servis zaten kapalı olduğu için tablo lock önemli değil.

### Redis Seviyesi

`redis_client.py` her pool için `max_connections` sınırı:

| Pool | `max_connections` | Kullanım |
|---|---|---|
| Ana pool (app) | `50` | API request'leri |
| ARQ pool | `20` | Worker job'ları |
| Cache pool | `20` | FastAPICache |
| Pub/sub pool | `20` | WS broadcast, auction stream |

### Uygulama Seviyesi (Backend)

Aynı V1.3 döneminde yapılan 14 kod düzeyinde iyileştirme:

| # | Dosya | Değişiklik | Etki |
|---|---|---|---|
| 1 | `models/stream.py` | `StreamLike.lazy="raise"` | Tüm like'ları her stream sorgusunda yüklemez |
| 2 | `models/listing.py` | `ListingLike.lazy="raise"` | Aynı |
| 3 | `models/story.py` | `StoryLike.lazy="raise"` | Aynı |
| 4 | `core/rate_limit.py` | `storage_uri="redis://"` (sync) | `async+redis://` coredis ≥3.4.0 gerektiriyor; venv'e kurulmadığından sync'e döndürüldü — rate limit check için fark ihmal edilebilir |
| 5 | `core/ws_manager.py` | serialize-once + `orjson` | N kullanıcıya broadcast'te JSON N kez değil 1 kez üretilir |
| 6 | `routers/listings.py` | dead cache invalidation kaldırıldı | Hiç yazılmayan cache key'i silmeye çalışan ölü kod |
| 7 | `database.py` | `get_uow()` → `get_db()` session'ını paylaşır | Aynı request'te iki DB session yerine bir session |
| 8 | `routers/auth.py` | `COUNT(*)` → `EXISTS()` | Kullanıcı varlık kontrolü tam sayım yerine boolean |
| 9 | `services/feed/foryou_worker.py` | mget + pipeline + TTL | N kullanıcı × M ilan yerine 1 mget; pipeline ile toplu yazım; 1 saatlik TTL |
| 10 | `worker.py` | loop → `executemany`; `scan_iter` → direct delete | Tek DB round-trip; deterministic key silme |
| 11 | `use_cases/listings/get_video_feed.py` | `ORDER BY RANDOM()` → offset-based | Tam tablo sıralama yerine COUNT + random offset |
| 12 | `services/recommendation_service.py` | `RANDOM()` → `hashtext(id \|\| salt)` | Full-scan yerine index kullanabilir sıralama |
| 13 | `services/ml/faiss_service.py` | index build → `run_in_executor` | CPU-bound FAISS build event loop'u bloklamaz |
| 14 | `use_cases/feed/feed_queries.py` | `scan_iter("ad_campaign_budget:*")` → `smembers("ad_campaigns:active")` | Keyspace taraması yerine O(1) set lookup |

---

## 21. Operasyonel Tekilleştirme (V1.3)

### `teqlif-restart` — Tek Komut Deploy

V1.3 öncesinde bir deploy şu adımları gerektiriyordu:

```
ssh node1
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical
# ayrı terminal açıp:
journalctl -u teqlif -f
# sonra durum kontrolü:
systemctl status teqlif teqlif-worker teqlif-worker-critical
```

V1.3 sonrasında tek komut:

```bash
sudo teqlif-restart
```

**Mimari:** `teqlif-restart.sh` bir dispatcher'dır — `systemctl cat` ile yüklü servis dosyalarını kontrol ederek node'u tespit eder ve ilgili node-specific script'i çalıştırır.

| Node tespiti | Kriter |
|---|---|
| node1 | `teqlif.service` var + `teqlif-staging.service` yok |
| node2 | `cf-failover.service` var |
| node3 | `teqlif-staging.service` var |
| gateway | diğer hiçbiri yok |

Her node-specific script'in fazları:

| Node | Faz 1 | Faz 2 | Faz 3 | Faz 4 |
|---|---|---|---|---|
| node1 | git pull | teqlif+worker restart (canlı journal) | altyapı check | servis özeti |
| node2 | git pull | ai-proxy+cf-failover restart | servis özeti | — |
| node3 | git pull | teqlif-staging+worker restart (canlı journal) | ai-proxy restart | altyapı+monitoring check + özet |
| gateway | git pull | nginx -t + reload | servis özeti | — |

Hata durumunda: başarısız her servis için `systemctl status` + son 100 satır journal + `reset-failed` ipucu otomatik gösterilir.

**Ön koşullar:**
- Tüm node'larda git remote HTTPS olmalı: `git remote set-url origin https://github.com/tucibeyin/teqlif.git`
- `teqlif-restart.sh` execute bit'i: `chmod +x deploy/scale/V1.3/scripts/teqlif-restart.sh`
- Symlink: `sudo ln -sf /var/www/teqlif.com/deploy/scale/V1.3/scripts/teqlif-restart.sh /usr/local/sbin/teqlif-restart`

**Kaynak:** `deploy/scale/V1.3/scripts/teqlif-restart.sh` → `deploy/scale/V1.3/<node>/scripts/<node>_restart.sh`
