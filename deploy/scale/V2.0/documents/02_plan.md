# V2.0 Deployment Plan

**Durum:** Final  
**Bağlı belge:** [01_findings.md](01_findings.md)

---

## Temel Kurallar

1. **Sıfırdan kurulum — yeşil alan.** Her node Debian 13 fresh install. Migration yok, backward compatibility yok, V1.4 geçmişi yok. Her adım temiz bir sistemden başlar. Bu, tüm tasarım ve denetim kararlarını etkiler: legacy endpoint varsayımı yapılmaz, geçiş/shim/compat kodu yazılmaz, presigned upload V2.0'dan itibaren tek upload yöntemidir. "Eski kod bozulur" gerekçesiyle hiçbir kısıtlama gevşetilmez.
2. **Gizlilik sınırı.** WireGuard private key, `.env.*` dosyaları, `firebase-service-account.json` ASLA repoya girmez. Repodaki template dosyaları `<placeholder>` değerleriyle commit edilir.
3. **Tasarım prensipleri.** `documents/teqlif_architectural_decisions.md`, Clean Architecture ve Clean Code esas alınır.

---

## Node Envanteri

| Node | WG IP | Rol | CPU / RAM / Disk | Ağ | Fiziksel |
|------|-------|-----|-----------------|-----|---------|
| gateway1 | 10.10.0.2 | Edge Proxy #1 | 2c / 1.9 GB / 59 GB | ~1 Gbps | Netcup NUE |
| gateway2 | 10.10.0.9 | Edge Proxy #2 | 2c / 9.0 GB / 79 GB | ~4–7 Gbps | DELUXHOST AMS |
| node1 | 10.10.0.1 | Stream #1 (LiveKit) | 6c / 11.4 GB / 98 GB NVMe | ~1.9 Gbps | OVH FRA |
| node2 | 10.10.0.3 | AI Proxy | 1c / 1.4 GB / 14.7 GB | ~300 Mbps | RackNerd BUF |
| node3 | 10.10.0.4 | Staging | 4c / 3.8 GB / 49 GB | ~400 Mbps | ZAP VA |
| node4 | 10.10.0.6 | Stream #2 (LiveKit) | 6c / 11.4 GB / 98 GB NVMe | ~1.9 Gbps | OVH FRA |
| node5 | 10.10.0.5 | Core #1 (Primary) | 4c AMD EPYC / 7.8 GB / 49 GB NVMe | ~1 Gbps | ZAP MUN |
| node6 | 10.10.0.7 | Core #2 (Standby) | 3c / 7.7 GB / 79 GB | ~2–4 Gbps | DELUXHOST AMS |
| node7 | 10.10.0.8 | Storage #1 | 2c / 2.9 GB / 10 GB SSD + 1 TB HDD | ~1.1 Gbps | DELUXHOST NL |
| node8 | 10.10.0.12 | Storage #2 | 2c / 2.9 GB / 10 GB SSD + 1 TB HDD | ~1.1 Gbps | DELUXHOST NL |
| node9 | 10.10.0.13 | Backup + Monitor + ClickHouse | 4c(8t) / 31 GB ECC / 3.5 TB HDD RAID-1 | ~480 Mbps | OVH LIM (KS-1-B) |

**Sanal IP'ler (Keepalived — wg0 üzerinde):**
- `10.10.0.10` → PostgreSQL VIP (node5 primary ↔ node6 standby)
- `10.10.0.11` → Redis VIP (node5 primary ↔ node6 standby)

---

## Mimari Referans — Topoloji Özeti

> **Nasıl kullanılır:** Bu bölüm deployment guide değil, çalışma anındaki topolojinin **tek referans noktası**dır. Bir şeyin nerede ve hangi modda çalıştığını bulmak için buraya bak; kurulum detayı için ilgili Faz bölümüne git.

---

### Node ve WireGuard Mesh

| Node | WG IP | DC / Sağlayıcı | Ortam | Rol | Bant |
|------|-------|----------------|-------|-----|------|
| gateway1 | 10.10.0.2 | Netcup NUE | Prod | Edge Proxy #1 — nginx, API girişi | ~1 Gbps |
| gateway2 | 10.10.0.9 | DELUXHOST AMS | Prod | Edge Proxy #2 — nginx, API girişi | ~4–7 Gbps |
| node1 | 10.10.0.1 | OVH FRA | Prod | Stream #1 — LiveKit SFU | ~1.9 Gbps |
| node2 | 10.10.0.3 | RackNerd BUF | Prod | AI Proxy Primary | ~300 Mbps |
| node3 | 10.10.0.4 | ZAP VA | **Hybrid** | Staging (tam stack) + AI Proxy Warm | ~400 Mbps |
| node4 | 10.10.0.6 | OVH FRA | Prod | Stream #2 — LiveKit SFU | ~1.9 Gbps |
| node5 | 10.10.0.5 | ZAP MUN | Prod | Core Primary — FastAPI, PG, Redis | ~1 Gbps |
| node6 | 10.10.0.7 | DELUXHOST AMS | Prod | Core Standby — failover hedefi | ~2–4 Gbps |
| node7 | 10.10.0.8 | DELUXHOST NL | Prod | Storage #1 — MinIO, teqlif + teqlif-dm | ~1.1 Gbps |
| node8 | 10.10.0.12 | DELUXHOST NL | Prod | Storage #2 — MinIO, teqlif + teqlif-dm | ~1.1 Gbps |
| node9 | 10.10.0.13 | OVH LIM KS-1-B | Prod | Monitor + Backup + ClickHouse | ~480 Mbps |

**Tüm 11 node her node'la doğrudan WG tüneli kurar (full mesh, MTU=1420, port=51820).**

**Sanal IP'ler (Keepalived, wg0 üzerinde — node5↔node6 arasında failover):**

| VIP | IP | Kapsadığı Servisler | Normal Sahibi |
|-----|-----|---------------------|---------------|
| PG VIP | 10.10.0.10 | PostgreSQL :5432, PgBouncer hedef IP | node5 |
| Redis VIP | 10.10.0.11 | redis-core :6379, redis-orch :6380 | node5 |

---

### Trafik Akışı (Prod)

```
İnternet
  │
  ├─ HTTPS api.teqlif.com  ──→ Cloudflare Proxy ──→ gateway1 / gateway2 (Round Robin)
  │   (JSON sinyali — auth,     yalnızca küçük JSON      │
  │    metadata, WebSocket)      paketleri geçer          └─ nginx → 10.10.0.10:8000 (VIP)
  │                                                                    → node5 (normal)
  │                                                                    → node6 (failover)
  │
  ├─ HTTPS media.teqlif.com ─→ Cloudflare Cache ──→ node7 / node8   ← Media OKUMA (GET)
  │                              veya Bypass         nginx + MinIO
  │
  ├─ HTTPS uploads.teqlif.com → DNS Only (bypass CF) ──→ node7 / node8  ← Media YAZMA (PUT)
  │   (presigned PUT — photo,                            MinIO presigned URL doğrular
  │    video, DM media)          ← Gateway'den GEÇMEZ; bandwidth kısıtı
  │
  ├─ WSS live1.teqlif.com  ───→ DNS Only (bypass Cloudflare) ──→ node1 :7880 / TURN :3478
  │   WSS live2.teqlif.com                                    ──→ node4 :7880 / TURN :3478
  │   (WebRTC UDP 50000-60000)   ← Gateway'den GEÇMEZ; bandwidth kısıtı
  │
  └─ HTTPS staging.teqlif.com ─→ Cloudflare Proxy ──→ gateway1 / gateway2
                                                           │
                                                           └─ nginx → 10.10.0.4:8000 (node3, WireGuard)
```

**Gateway felsefesi:** Gateway = yalnızca sinyal kanalı. Küçük JSON (auth, metadata, WebSocket sinyal) taşır; byte akışı (media, video, stream) ilgili node'a doğrudan gider. AI proxy trafiği iç mesh üzerinden akar: `uygulama (node5) → ai_proxy:active_url → node2/node3/node5`. Bkz. §0.3.3.

---

### Uygulama Servisleri — Node × Durum Matrisi

> **Durum:** ● Aktif (enabled, always-on) · ○ Standby (installed + disabled, failover'da başlar) · ◐ Warm (active, ikincil öncelik) · △ Cold (disabled, orchestrator başlatır) · ≡ Replica · — Yok

#### Core Uygulama (FastAPI)

| Servis | node5 | node6 | node3 | Notlar |
|--------|-------|-------|-------|--------|
| teqlif.service (prod API :8000) | **●** | ○ | — | node6 failover'da: `systemctl start teqlif` |
| teqlif-worker.service (prod) | **●** | ○ | — | ARQ background jobs |
| teqlif-worker-critical.service (prod) | **●** | ○ | — | Öncelikli job kuyruğu |
| teqlif.service (staging API :8000) | — | — | **●** | `.env.staging`, local PG/Redis |
| teqlif-worker.service (staging) | — | — | **●** | Staging bağımsız stack |
| teqlif-worker-critical.service (staging) | — | — | **●** | |

#### AI Proxy

| Servis | node2 | node3 | node5 | Failover Sırası | Notlar |
|--------|-------|-------|-------|-----------------|--------|
| teqlif-ai-proxy.service :8001 | **●** | **◐** | △ | 1 → 2 → 3 | Orchestrator `ai_proxy:active_url` key'i yönetir |
| Mod | Primary | Warm Standby | Cold Last Resort | ~6s otomatik | node5 MemoryMax=600M |

#### Streaming (LiveKit)

| Servis | node1 | node4 | Mod | Notlar |
|--------|-------|-------|-----|--------|
| livekit-server.service :7880 | **●** | **●** | Aktif-Aktif (bağımsız) | Orchestrator `stream_score` ile yönlendirir |
| live1.teqlif.com | DNS→node1 | — | DNS Only | WebRTC için Cloudflare bypass |
| live2.teqlif.com | — | DNS→node4 | DNS Only | |
| Aktif session failover | YOK | YOK | — | Session kesilir; reconnect surviving node'a gider |

#### Gateway (nginx)

| Servis | gateway1 | gateway2 | Mod | Notlar |
|--------|----------|----------|-----|--------|
| nginx :80/:443 | **●** | **●** | Aktif-Aktif | Cloudflare her ikisine yük dengeler |
| Media/stream proxy | — | — | — | Gateway'den GEÇMİLYOR; bandwidth kısıtı |

---

### Veri Katmanı

#### PostgreSQL + PgBouncer (Aktif-Pasif)

| Bileşen | node5 | node6 | Erişim IP | Mod |
|---------|-------|-------|-----------|-----|
| PostgreSQL :5432 | **Primary** | ≡ Streaming Replica | 10.10.0.10 (VIP) | Keepalived failover; manüel failback |
| PgBouncer :6432 | **●** | ○ (failover'da enable+start) | 10.10.0.10:6432 | Transaction pooling |
| node3 PostgreSQL :5432 | — | — | 127.0.0.1 | Staging lokal, izole |
| Failover süresi | — | — | ~30s | Keepalived otomatik |
| Failback | — | — | Manüel | `nopreempt` — otomatik preempt yok |

#### Redis (3 Instance — Aktif-Pasif)

| Instance | Port | node5 | node6 | VIP | Amaç |
|----------|------|-------|-------|-----|------|
| redis-core | 6379 | **Primary** | ≡ Replica (via VIP) | 10.10.0.11:6379 | Session cache, uygulama cache |
| redis-orch | 6380 | **Primary** | ≡ Replica (via VIP) | 10.10.0.11:6380 | Orchestrator state, edge metrics |
| redis-guardian | 6382 | **Primary** | ≡ Replica (direkt IP 10.10.0.5) | — VIP YOK — | Guardian topology, job state, election |
| node3 Redis | 6379 | — | — | 127.0.0.1 | Staging lokal, izole |

#### MinIO — Nesne Depolama (Dual-Write)

| Bileşen | node7 (10.10.0.8) | node8 (10.10.0.12) | Mod |
|---------|-------------------|--------------------|-----|
| MinIO server :9000 | **●** Aktif | **●** Aktif | Her ikisi her zaman çalışır |
| Bucket: teqlif | **●** | **●** | Dual-Write: uygulama her ikisine paralel yazar |
| Bucket: teqlif-dm | **●** | **●** | Dual-Write; DM medyası ayrı bucket |
| Bucket versioning | **●** | **●** | 90 gün; silinmiş nesne kurtarma |
| Senkronizasyon | Kaynak | Hedef (ve tersi) | Gecelik `mc mirror` çift yönlü (02:00 UTC) |
| nginx proxy :443 | **●** + 1GB SSD cache | **●** + 1GB SSD cache | CF→media.teqlif.com→node7; fallback node8 |
| Erişim URL'leri | `media.teqlif.com` (okuma — CF Proxied + CDN cache) | `uploads.teqlif.com` (yazma + DM — DNS Only, CF bypass) | Okuma: CF edge'de cache'lenir (HDD yükü azalır); Yazma: presigned imza CF proxy'den geçemez |

> **teqlif-dm:** DM medyası için ayrı bucket — aynı MinIO instance'ları üzerinde. Ayrı node veya process değil.

---

### HA Mod Özeti

| Katman | Mod | RTO | Otomatik mi? |
|--------|-----|-----|--------------|
| **Gateway** | Aktif-Aktif (CF load balance) | Sıfır (CF yönlendirmesi anlık) | ✓ |
| **FastAPI / Worker** | Aktif-Pasif (node5→node6) | ~30s | ✓ Keepalived + failover script |
| **PostgreSQL** | Aktif-Pasif (streaming replication) | ~30s | ✓ (failback manüel) |
| **Redis core/orch** | Aktif-Pasif (VIP üzerinden) | ~30s | ✓ Keepalived |
| **Redis guardian** | Aktif-Pasif (direkt IP) | ~30s | ✓ Failover script |
| **AI Proxy** | 3 kademeli cascade | ~6s / ~6s | ✓ Orchestrator TTL |
| **LiveKit Stream** | Aktif-Aktif (bağımsız node'lar) | Anlık (yeni stream) | ✓ Yeni session; aktif session failover YOK |
| **MinIO** | Dual-Write + nightly mirror | 0 (yazma hataları raporlanır) | ✓ (okuma fallback nginx) |
| **node5 kalıcı arıza** | node6 permanent primary; yeni standby | ~2 saat | ✗ Manüel |
| **node1 + node4 eş zamanlı** | Stream tamamen kesilir | Dakikalar | ✗ Bilinen SPOF |

---

### Monitoring ve Backup (node9)

| Servis | Port | Mod |
|--------|------|-----|
| Prometheus | :9090 | Aktif, 11 node scrape (15s), 30 gün TSDB |
| Grafana | :3000 | Aktif, sadece WG erişimi |
| Loki | :3100 | Aktif, 7 gün log, tüm node promtail push eder |
| Alertmanager | :9093 | Aktif → Telegram `#alerts` / `#ops` |
| ClickHouse | :8123 | Aktif, prod analytics (prod trafik → node9:8123) |
| pg_receivewal | — | Sürekli WAL stream (node5 VIP:5432 → /opt/teqlif/backups/postgres/wal) |
| pg_basebackup | — | Haftalık timer (Pazar 01:00 UTC) |
| pg_dump | — | Günlük timer (03:00 UTC) |
| redis_backup | — | Günlük timer (03:30 UTC) |
| clickhouse_backup | — | Günlük timer (04:00 UTC) |
| offsite_sync | — | Günlük rclone → B2/Hetzner (04:30 UTC) |

---

### Tüm 11 Node'da Çalışan Servisler

Her node kurulumunda şunlar zorunlu:

| Servis | Amaç |
|--------|------|
| WireGuard (wg0) | Mesh tüneli — tüm iç iletişim buradan |
| teqlif-guardian.service :9200 `/metrics` | Prometheus metrik toplama — node-exporter yerine guardian içinde (node_exporter kurulmaz) |
| promtail | Log → node9 Loki :3100 push |
| teqlif-guardian.service | Guardian agent — metrik, sağlık, heartbeat, election, komut executor |
| fail2ban | SSH brute-force koruması |
| logrotate (teqlif) | `/var/log/teqlif/**` haftalık rotate, 8 hafta, compress |

---

## Dizin Yapısı ve Yetkiler

Her node'da uygulanacak standart dizin yapısı. Rol gerektirmedikçe oluşturulmaz.

### Tüm Node'lar (Ortak)

```
/var/www/teqlif.com/           # monorepo — git clone; 755 tucibeyin:tucibeyin
  backend/                     # FastAPI, ARQ, scripts
  deploy/                      # şablonlar, scriptler
  mobile/                      # Flutter
  frontend/                    # Web
  .venv/                       # Python virtualenv (tüm node'larda burada)

/etc/teqlif/                   # 755 root:root
  node.conf                    # 644 root:root  ← NODE_NAME, NODE_ROLE (sır değil)
  .env.production              # 600 tucibeyin:tucibeyin  ← tüm sırlar

/var/lib/teqlif/               # 755 tucibeyin:tucibeyin  ← guardian_state.json burada tutulur

/var/log/teqlif/               # 755 tucibeyin:tucibeyin  ← 755: promtail (system user) dizine girebilmeli
  api/
  worker/
  orchestrator/
  minio/                       # sadece storage node'larında (Faz 6.3)

/etc/wireguard/
  wg0.conf                     # 600 root:root  ← private key burada
```

### Gateway (gateway1, gateway2)

```
/etc/ssl/teqlif/               # 700 root:root  ← CF Origin cert
  cf-origin.crt                # 644 root:root
  cf-origin.key                # 600 root:root
```

### Core (node5 Primary + node6 Standby)

```
/var/lib/redis-core/           # 750 redis:redis  ← Redis RDB+AOF (core, port 6379)
                               # redis-orch ephemeral (save ""); dir ayarı yok, default /var/lib/redis

/etc/keepalived/
  secrets/                     # 700 root:root  ← failover.env burada; dizin de kilitli
    failover.env               # 600 root:root  ← Telegram token, Redis pass, WG pubkey'ler
  scripts/                     # 750 root:root
    wg_vip_node5.sh            # 750 root:root  (node5'te)
    wg_vip_failover.sh         # 750 root:root  (node6'da)
```

**node9'a özgü:**
```
/data/clickhouse/              # clickhouse:clickhouse  ← ClickHouse veri + backup (node9 lokal)
/opt/teqlif/backups/           # tucibeyin:tucibeyin 700 ← PG WAL/dump, Redis, off-site log
```

### Stream (node1, node4)

```
/etc/livekit/                  # 700 root:root  ← livekit.yaml (API key/secret)
```

### Storage (node7, node8)

```
/mnt/data/                     # 755 root:root  ← HDD/vdb mount noktası
  minio/                       # 700 tucibeyin:tucibeyin  ← MinIO verisi

/var/cache/nginx/storage       # www-data:www-data  ← nginx proxy cache
/etc/ssl/teqlif/               # 700 root:root  ← CF Origin cert (storage nginx TLS için)
  cf-origin.crt                # 644 root:root
  cf-origin.key                # 600 root:root
```

### Monitoring + Backup + ClickHouse (node9)

```
/opt/teqlif/
  backups/                     # 700 tucibeyin:tucibeyin  ← tüm backup verileri; repoya girmez
    postgres/
      wal/                     # pg_receivewal WAL segmentleri
      basebackup/              # pg_basebackup
      dump/                    # pg_dump
    redis/                     # redis-cli --rdb dump
    clickhouse/                # ClickHouse local backup
    minio/                     # MinIO cold archive (node7+8'den rsync)
    offsite-log/               # offsite rsync çıktıları
  scripts/                     # 750 tucibeyin:tucibeyin  ← backup scriptleri

# node9 disk yapısı:
# /          → 150 GB (OS + servisler)
# /data      → 3.5 TB (ClickHouse data + Prometheus TSDB + Loki chunks + backup arşivi)
```

### Staging (node3)

```
# node3: saf staging node — monitoring ve backup node9'a taşındı
# /var/www/teqlif.com aynı monorepo — /etc/teqlif/.env.staging (600 tucibeyin:tucibeyin)
```

---

**Kural:** Systemd `User=tucibeyin`. `.env.production` sahibi `tucibeyin`, mod `600` — root olarak `cp` yapılsa dahi `chown tucibeyin:tucibeyin` zorunlu; aksi halde servis okuyamaz. `wg0.conf` sahibi `root`, mod `600` — private key root'a kilitli. `/etc/keepalived/secrets/` dizini `700 root:root` — dosyanın 600 olması tek başına yeterli değil, dizin de kilitlenmeli. Tüm node'larda monorepo `/var/www/teqlif.com/`'da, `git pull` ile güncellenir.

---

## Faz Bağımlılık Haritası

```
Faz 0  (Kod — lokalde)
  └── Faz 1  (OS Temeli — tüm node'lar)
        └── Faz 2  (WireGuard Mesh — tüm node'lar)
              └── Faz 3  (Rol Bazlı OS Tuning — tüm node'lar)
                    └── Faz 4  (Veri Katmanı HA — node5 + node6)
                          └── Faz 5  (Core App — node5 + node6)
                                ├── Faz 6  (Storage — node7 + node8)        ← 5'ten sonra paralel
                                ├── Faz 7  (Gateway — gateway1 + gateway2)  ← 5'ten sonra paralel
                                └── Faz 8  (Stream + AI Proxy)              ← 5'ten sonra paralel
                                      ↓  (6+7+8 tamamlanınca)
                                     Faz 9  (Guardian Koordinatör)
                                       └── Faz 10  (node9 — Monitoring + Backup + ClickHouse)
                                             └── Faz 11  (Staging — node3)
                                                   └── Faz 12  (Prod + Mobile)
                                                         └── Faz 13  (node9 Doğrulama + Tam Entegrasyon)
```

---

## §0.0 — Secrets Üretimi (VPS Kurulumundan Önce — Lokalde Bir Kez)

Tüm paylaşılan secret'lar ilk node kurulumuna başlamadan lokal Mac'te üretilir ve `~/teqlif-secrets.env` dosyasına yazılır. **Bu dosya asla repoya girmez.**

```bash
# Oluştur ve koru
touch ~/teqlif-secrets.env
chmod 600 ~/teqlif-secrets.env
```

### Üretilecek Secret'lar

| Değişken | Komut | Kullanıldığı Node'lar |
|----------|-------|----------------------|
| `teqlif_db_password` | `openssl rand -hex 32` | node5, node6, node9 (PG + backup) |
| `replicator_password` | `openssl rand -hex 32` | node5 (PG streaming replication) |
| `core_redis_pass` | `openssl rand -hex 32` | Tüm 11 node |
| `orch_redis_pass` | `openssl rand -hex 32` | Tüm 11 node |
| `guardian_redis_pass` | `openssl rand -hex 32` | Tüm 11 node |
| `teqlif_ch_password` | `openssl rand -hex 32` | node5, node6, node9 |
| `secret_key` | `openssl rand -hex 32` | node5, node6 (JWT imzası) |
| `staging_secret_key` | `openssl rand -hex 32` | node3 (staging JWT — prod'dan farklı) |
| `staging_pg_pass` | `openssl rand -hex 32` | node3 (lokal staging PG) |
| `staging_redis_pass` | `openssl rand -hex 32` | node3 (lokal staging Redis) |
| `minio_staging_root_user` | `openssl rand -hex 16` | node3 (lokal MinIO staging — prod'dan izole) |
| `minio_staging_root_password` | `openssl rand -hex 32` | node3 (lokal MinIO staging) |
| `livekit_staging_api_key` | `openssl rand -hex 16` | node3 (lokal LiveKit staging — prod'dan izole) |
| `livekit_staging_api_secret` | `openssl rand -hex 32` | node3 (lokal LiveKit staging) |
| `minio_root_user` | `openssl rand -hex 16` | node7, node8, node5, node6 |
| `minio_root_password` | `openssl rand -hex 32` | node7, node8, node5, node6 |
| `ai_proxy_internal_token` | `openssl rand -hex 32` | node2, node3, node5, node6 |

External servis credential'ları (LIVEKIT_API_KEY, BREVO_API_KEY, FIREBASE vb.) ilgili sağlayıcı panelinden alınır; `~/teqlif-secrets.env`'e aynı formatta eklenir.

WireGuard keypair'leri her node'da ayrı üretilir (Faz 2 — `wg genkey | tee private.key | wg pubkey`); public key'ler `~/teqlif-secrets.env`'e not edilir.

### Checklist

- [ ] `~/teqlif-secrets.env` oluştur, 600 ile koru — asla repoya ekleme (`secrets*.env` `.gitignore`'da zaten yok; ekle veya home dizininde tut)
- [ ] Tüm satırları `KEY=<üretilen_değer>` formatında doldur
- [ ] External service credential'larını (LiveKit, Brevo, Firebase, APNS, Google, Sentry, Telegram, Cloudflare Turnstile) ilgili panellerden al ve dosyaya ekle
- [ ] Template dosyaları oluştuktan sonra `<placeholder>` değerlerini bu dosyadaki karşılıklarıyla değiştirerek `.env.production` / `.env.staging` oluşturulur

---

## Faz 0 — Kod Hazırlığı (Lokalde)

**Amaç:** V2.0 mimarisine uygun tüm kod değişikliklerini VPS'e dokunmadan repoda hazırla. Bu fazın tamamı lokalde yapılır, merge + push edilir.

### 0.1 `edge_orchestrator.py` Kaldırma

- [ ] `backend/app/services/edge_orchestrator.py` sil
- [ ] Import eden tüm router/servis dosyalarında referanslar temizle (≈10 dosya)
- [ ] `config.py`'den kaldır: `edge_livekit_urls`, `edge_minio_urls`, `minio_storage_quota_percent`, `edge_metrics_interval_sec`

### 0.2 Guardian Altyapısı — Redis + Local Agent

#### 0.2.1 Redis Altyapısı

- [ ] `config.py`: `orch_redis_url: str`, `guardian_redis_url: str` ekle
- [ ] `redis_client.py`: `get_orch_redis()`, `get_guardian_redis()` fonksiyonları
- [ ] `backend/app/services/orch_client.py` oluştur — 4 kademeli fallback:
  ```
  1. Orch-redis (orch:routing:* keys) — normal yol
  2. /var/lib/teqlif/guardian_state.json okuma — orch-redis erişilemezse
     Okuma: async open + JSON parse; JSONDecodeError veya IOError → 3. kademeye geç
     Freshness: updated_at <= 90s → taze, kullan
     updated_at > 90s → stale, 3. kademeye geç (stale JSON 4. kademedeki son çaredir, 2'de YOK)
     İlk kurulum: dosya yoksa → 3. kademeye geç (hata değil, normal)
  3. Stale guardian_state.json — son bilinen topoloji (UDP lider modunda JSON güncellenmez; stale
     veri hardcoded config'den her zaman iyidir; JSONDecodeError veya IOError → 4. kademeye geç
  4. config.py defaults — tüm kaynaklar başarısız olursa mutlak son çare
     Zorunlu alanlar: stream_nodes=[node1_ip, node4_ip], storage_nodes=[node7_ip, node8_ip],
     ai_proxy_url=node2_ip — en sağlam node'lar hardcoded (node5 FastAPI = zaten bu process,
     node1/node4 LiveKit = bağımsız DC, node7/node8 storage = bağımsız DC)
     Config olmaksızın başlatmayı ENGELLEME — app çalışmaya devam eder, capacity azalır
  ```
  - `get_stream_node()`, `get_storage_nodes()`, `get_ai_proxy_url()` — hepsi bu 4 kademeli zinciri kullanır
  - Fallback kademesi Prometheus metric olarak yayınlanır: `orch_client_fallback_level{level="redis|json_fresh|json_stale|config"}` — stale veya config'e düşünce alert

#### 0.2.2 Guardian Agent — `backend/scripts/guardian_agent.py`

`edge_metrics_agent.py` **kaldırılır**, yerine `guardian_agent.py` gelir. Her node'da `teqlif-guardian.service` adıyla çalışır. İki bağımsız goroutine:

**A) Local Agent** — her 3s, lider olsun olmasın:

```
node.conf oku (YAML) → node_id, env, guardian_priority, components, network, hardware
  │
  ├── Metrik topla (psutil):
  │     cpu_percent, cpu_cores, load_1m/5m/15m
  │     ram_used_percent, ram_free_gb, swap_used_gb
  │     disk_{total,used,free}_gb (tüm mount'lar için)
  │     net_out_mbps, net_in_mbps
  │     net_out_percent = net_out_mbps / network.speed_mbps * 100
  │     tcp_connections (ss -s)
  │
  ├── Component health kontrol (node.conf components listesinden):
  │     health_check.type == "http" → httpx GET, timeout=2s → ok/failed/timeout
  │     health_check.type == "cmd"  → subprocess(shell=True, env=os.environ), timeout=3s → ok/failed
  │     # cmd shell=True + os.environ zorunlu: cmd'de $CORE_REDIS_PASS gibi env var referansları
  │     # EnvironmentFile'dan yüklenen değerlerle expand edilmeli — shell=False ile literal kalır
  │     rol özel telemetri:
  │       stream    → livekit_active_rooms, livekit_participants (LiveKit API)
  │                   stream_score = net_out_percent*0.4 + cpu*0.3 + ram*0.3
  │       storage   → minio_health (HTTP), minio_io_reads/writes (MinIO metrics API)
  │       gateway   → nginx_active_connections, nginx_rps (nginx stub_status)
  │       core      → pg_replication_lag_sec, redis_replication_lag_sec (node6'da)
  │
  ├── Orch-redis'e yaz (guardian varsa):
  │     HSET edge:metrics:{node_id}  → tüm metrikler  EXPIRE 6
  │     HSET edge:health:{node_id}   → component sağlıkları  EXPIRE 6
  │     HSET edge:telemetry:{node_id}→ rol telemetrisi  EXPIRE 10
  │
  ├── guardian_state.json'u oku → lokal routing kararlarını önbelleğe al
  │     (guardian veya orch-redis erişilemez olsa bile uygulama bu dosyayı okur)
  │
  └── Local healer:
        component health == "failed" + systemd restart count > threshold
        → systemctl reset-failed {unit} && systemctl start {unit}
        → guardian:events'e "local_heal:{node_id}:{component}" yaz
```

**B) Heartbeat + Election** — her 5s UDP port 9901:

> **V2.0 kapsamı:** Lider seçimi guardian-redis NX (Adım 1) ve UDP heartbeat basit priority karşılaştırmasıyla (Adım 2) sınırlı tutulur. Tam Bully algorithm ve gelişmiş partition toleransı V2.1'e ertelenir. V2.0'da node5+node6 ikisi de down olursa lider seçilmez → coordinator çalışmaz → lokal agentlar orch-redis'e yazmaya devam eder, guardian_state.json güncellenmez. Bu kabul edilen bir sınırdır.

```
UDP broadcast → tüm WireGuard peer'larına:
  {"node_id":"node5","priority":100,"is_leader":false,"ts":1727500000}

Dinle → peer heartbeat'lerini tablo olarak tut:
  peers = {"node6": {"priority":90,"last_seen":ts}, ...}

Lider seçimi (2 adımlı — V2.0):

  Adım 1 — Guardian Redis varsa (hızlı yol):
    SET guardian:leader "{node_id}" EX 15 NX
    → başarılı: lider ol, koordinatörü başlat
    → başarısız: lideri takip et, TTL izle

  Redis kopmasında graceful backoff (Keepalived race condition önlemi):
    redis_unavailable_since = None
    Redis'e bağlanılamadığında: redis_unavailable_since = now()  (ilk kopma anı; tekrar bağlanınca sıfırla)
    Adım 2'ye geçiş koşulu: Redis HÂLÂ ulaşılamıyor VE (now() - redis_unavailable_since) > 20s
    # 20s ≥ Keepalived failover süresi (tipik ~3-5s, kötü senaryo ~15s)
    # Bu pencere içinde Redis geri gelirse (Keepalived tamamlanır) → Adım 2 hiç başlamaz
    # Election thrashing riski: guardian:leader TTL=15s dolarken UDP election başlarsa,
    #   Redis geri gelince iki eş zamanlı election oluşabilir → 20s backoff bunu önler

  Adım 2 — Guardian Redis yoksa VE 20s geçtiyse (yavaş yol — basit priority):
    son 10s içinde heartbeat gelen peer'ları bul
    kendi priority > tüm reachable peer'ların priority → UDP lider ol (standalone)
    değilse → beklemeye devam et (split-brain riskinden kaçın)

    UDP modunda lider seçildiğinde — salt pasif davranış (V2.0 sınırı):
      ÖNEMLİ: Redis down olduğu için Command Executor (guardian:cmd:{node_id}) çalışamaz.
      UDP lider şunu YAPAR:
        - Telegram #alerts CRITICAL: "guardian-redis erişilemez; UDP fallback lider seçildi.
          Komut kanalı kapalı. Otomatik iyileştirme devre dışı. Manuel müdahale gerekebilir."
      UDP lider şunu YAPMAZ:
        - coordinator_loop başlatmaz (Redis gerektiren tüm operasyonlar başarısız olur)
        - routing değiştirmez, playbook yürütmez, CF DNS güncellemez
        - guardian_state.json broadcast yapmaz (guardian:topology okunamaz)
      Redis geri geldiğinde: redis_unavailable_since = None → Adım 1'e geç → yeni Redis tabanlı election

  Adım 3 — Lider keepalive:
    Lider seçildi → EXPIRE guardian:leader 15  (her 10s)
    # NOT: SET ... NX KULLANMA — NX yalnızca key yokken set eder;
    #      lider key'i zaten tuttuğu için NX başarısız olur → TTL yenilenomez → 15s'de expire
    Lider düştü (heartbeat kesildi + Redis TTL doldu) → yeniden seçim
```

**C) Command Executor** — guardian-redis pub/sub `guardian:cmd:{node_id}`:

```python
ALLOWED_COMMANDS = {
    "start_service":   lambda unit: systemctl("start", unit),
    "stop_service":    lambda unit: systemctl("stop", unit),
    "restart_service": lambda unit: systemctl("restart", unit),
    "reset_failed":    lambda unit: systemctl("reset-failed", unit),
    "reload_config":   lambda unit: systemctl("reload", unit),
    "cleanup_files":   lambda path, days: cleanup_old_files(path, days),
    "report_now":      lambda: force_metrics_push(),
}
# Sonuç: guardian:events XADD {"type":"cmd_result","node":...,"status":"ok/failed"}
# NOT: systemctl() helper → subprocess(["sudo", "systemctl", action, unit], ...)
#      teqlif-guardian User=tucibeyin (non-root) — direkt systemctl çağrısı Permission Denied verir.
#      §2.6 sudoers kuralı olmadan Local Healer hiçbir zaman çalışmaz.
```

- [ ] `deploy/scale/V2.0/node.conf.examples/` dizini oluştur — her rol için örnek şablon
- [ ] `.env.production` template'lerinden `NODE_CAPABILITIES`, `NODE_ROLE`, `INTERFACE_SPEED_MBPS` kaldır → bunlar artık `node.conf`'tan okunuyor
- [x] `deploy/scale/V2.0/systemd/teqlif-guardian.service` şablonu oluştur (tüm node'larda aynı unit dosyası)

### 0.3 Storage Service + LiveKit Reconnect Fix

#### 0.3.1 LiveKit Reconnect — stream.livekit_url Sorunu

`stream.livekit_url` stream yaratılırken DB'ye yazılır ve sabit kalır. Bu node düşünce sorun yaratır:
- `routers/streams.py` reconnect endpoint'i DB'deki `stream.livekit_url`'yi döndürür → dead node URL
- Mobile'a gönderilen URL artık geçersiz → bağlantı başarısız

**Fix:** Reconnect endpoint DB'deki URL'yi değil, orch-redis'ten güncel stream node'u okur:

```python
# routers/streams.py — /streams/{id}/token (reconnect)
# ÖNCE: node_url = stream.livekit_url  ← DB'den; dead olabilir
# SONRA:
from app.services.orch_client import get_stream_node

async def reconnect_stream(stream_id, ...):
    node = await get_stream_node()          # orch-redis → guardian_state.json → config
    if node:
        node_url = node["livekit_url"]
    else:
        node_url = stream.livekit_url       # hiçbir kaynak yoksa DB fallback (son çare)
```

**Önemli sınır:** Aktif WebRTC session'ları taşınamaz. node1 düşerse o node'daki aktif stream'ler kesilir. Reconnect yeni token oluşturur → kullanıcı yeni node'a bağlanır ama aynı room'u değil, yeni bir session başlatır. Bu V2.0'da kabul edilen bir sınırdır; belgelenmeli.

- [ ] `routers/streams.py`: reconnect endpoint `stream.livekit_url` → `orch_client.get_stream_node()` ile değiştir
- [ ] `routers/calls.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `worker.py`: `allocate_node()` çağrıları → `orch_client.get_stream_node()`
- [ ] `tasks/video_tasks.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `routers/webhooks.py`: stream node referansları → `orch_client`

#### 0.3.2 Storage Service — Dual-Write + URL Şeması

`storage_service.py` baştan yazılır:

- [ ] `_build_public_url()`: node_id kaldır → `settings.media_host/{bucket}/{key}` döndür
  (`uploads_host` yalnızca S3 PUT endpoint'i — DB'ye ve mobile'a dönen URL her zaman `media_host` olmalı)
- [ ] `upload_bytes()`: `orch_client.get_storage_nodes()` listesindeki tüm node'lara `asyncio.gather` ile paralel PUT
  Partial failure: her PUT sonucu ayrı ayrı kontrol edilir. En az 1 başarılı → yükleme başarılı. 0 başarılı → hata fırlat.
  Partial success log: "node7 ok, node8 failed" → guardian degraded alert üretir, veri kaybı olmaz.
- [ ] `upload_file_dm()`: aynı dual-write mantığı
- [ ] `delete_object()`: `storage_node_id` DB kolonunu okur, sadece o node'dan siler
- [ ] DB: `storage_node_id` kolonu için Alembic migration
- [ ] `scripts/cleanup_orphaned_storage.py`: aylık ARQ job — PostgreSQL'deki aktif media key'lerini (`media` + `pending_uploads` tabloları) ile MinIO objelerini karşılaştır; yetim dosyaları (`mc rm`) her iki node'dan sil; node5'te §6.9'daki `teqlif-storage-cleanup.timer` aylık tetikler
  **Grace period zorunlu:** MinIO objesinin `last_modified` ≥ 24 saat önce olması şartı — aktif upload (henüz /complete çağrılmamış) `pending_uploads`'ta görünür, ama DB insert başarısız/MinIO write başarılı race condition'ına karşı 24h buffer kesindir; yeni oluşturulan hiçbir dosyaya dokunulmaz

#### 0.3.3 Upload Mimarisi — Presigned PUT (Gateway Bypass)

**Felsefe:** Gateway yalnızca JSON sinyal taşır. Dosya byte'ları doğrudan storage node'larına gider.

| Trafik türü | V1.x (mevcut) | V2.0 hedefi |
|-------------|---------------|-------------|
| LiveKit stream (WebRTC) | DNS Only → node1/node4 | ✓ Zaten direkt |
| Media okuma (GET) | DNS Only → node7/node8 | **CF Proxied → CF CDN edge cache → node7/node8** |
| Media yükleme — fotoğraf | gateway → node5 → MinIO | **Presigned PUT → node7/node8 direkt** |
| Media yükleme — video | gateway → node5 → MinIO | **Presigned PUT → node7/node8 direkt** |
| MediaDM yükleme | gateway → node5 → MinIO | **Presigned PUT → node7/node8 direkt** |

**Yeni Upload Akışı — 3 Adım:**

```
[Adım 1 — Auth + Presign]  ~500B JSON  → gateway'den geçer (küçük sinyal)
  Mobile  →  POST /api/upload/presign
             {file_type: "image/jpeg"|"video/mp4", context: "story"|"message"|"profile", size_bytes: N}
  node5:
    - JWT doğrula, kullanıcı ban/kota kontrol
    - Boyut ve tür doğrula (max_upload_size, allowed_content_types)
    - DB: pending_uploads kaydı oluştur (upload_id, user_id, key, context, status=pending, expires_at=+15m)
    - storage_service.presign_put(key, expires=900, content_type) → MinIO presigned PUT URL üret
    - URL'i dahili endpoint'ten (MINIO_ENDPOINT) dış endpoint'e rewrite et (UPLOADS_HOST)
  Yanıt: {upload_id, put_url: "https://uploads.teqlif.com/teqlif/{key}", key, expires_in: 900}

[Adım 2 — Direkt Upload]  tüm byte'lar → GATEWAY YOK
  Mobile  →  PUT https://uploads.teqlif.com/teqlif/{key}
             Headers: Content-Type: image/jpeg, Content-Length: <size>
  node7/node8:  MinIO presigned URL imzasını doğrular → S3'e yazar
                Nginx fallback yapar (node7 çökerse node8 devralır). 
                Anlık dual-write işlemi MinIO Site Replication (§6.9) ile arka planda gerçekleşir.

[Adım 3 — Tamamlama + Post-İşleme]  ~200B JSON  → gateway'den geçer (küçük sinyal)
  Mobile  →  POST /api/upload/complete  {upload_id, key}
  node5:
    - DB: status=pending → processing
    - ARQ job kuyruğa: process_media_upload(upload_id, key, context)
  Yanıt: {media_url: "https://media.teqlif.com/teqlif/{key}", status: "processing"}

[ARQ Background — node5]  MinIO ↔ node5 dahili; internet trafiği yok
  process_media_upload(upload_id, key, context):
    - MinIO'dan key indir (WireGuard: node7 → node5, dahili)
    - context=video → FFmpeg thumbnail → MinIO'ya yükle (thumbnail_{key})
    - context=image → Pillow resize/optimize → MinIO'ya yükle
    - DB: status=ready, thumbnail_url güncelle, media_url güncelle
    - Redis WS event: upload_complete → istemciye bildir
    - Hata: status=failed → istemciye push notification
```

**Presigned PUT — `storage_service.py` eklentisi:**

```python
async def presign_put(self, key: str, expires: int = 900,
                      content_type: str = "application/octet-stream") -> str:
    """MinIO presigned PUT URL üretir; iç endpoint'i dış UPLOADS_HOST ile rewrite eder."""
    client = self._get_primary_client()
    raw_url = client.presigned_put_object(
        bucket_name=settings.minio_bucket,
        object_name=key,
        expires=timedelta(seconds=expires),
    )
    # MinIO URL'i dahili IP (MINIO_ENDPOINT) içerir — mobile erişemez.
    # uploads_host ile rewrite: https://uploads.teqlif.com/...
    # ZORUNLU: MinIO servisinde MINIO_SERVER_URL=https://uploads.teqlif.com set edilmeli
    # (bkz. §6.3). S3 V4 imzası Host header'ını içerir; MinIO, MINIO_SERVER_URL ile
    # uploads.teqlif.com'u kendi dahili adresiyle eşdeğer kabul eder — 403 olmaz.
    return raw_url.replace(settings.minio_endpoint, settings.uploads_host)

async def presign_put_dm(self, key: str, expires: int = 900) -> str:
    """DM private bucket için presigned PUT (teqlif-dm)."""
    client = self._get_primary_client()
    raw_url = client.presigned_put_object(
        bucket_name=settings.minio_dm_bucket,
        object_name=key,
        expires=timedelta(seconds=expires),
    )
    # Aynı MINIO_SERVER_URL zorunluluğu geçerli (bkz. §6.3).
    return raw_url.replace(settings.minio_endpoint, settings.uploads_host)
```

**DM Media Upload (Private Bucket):**

DM bucket `teqlif-dm` private'tır — presigned PUT URL geçici yazma izni verir (900s), okuma her zaman presigned GET ile yapılır (zaten mevcut `_presign_if_dm()`).

```
[Adım 1] POST /api/messages/media/presign  → {put_url, upload_id}
[Adım 2] PUT  https://uploads.teqlif.com/teqlif-dm/{key}  (direkt)
[Adım 3] POST /api/messages/media/complete {upload_id} → mesaj kaydet, WS push
```

**Değiştirilecek Dosyalar (Faz 0 checklist):**

- [ ] `storage_service.py`: `presign_put()` + `presign_put_dm()` + URL rewrite
- [ ] yeni `routers/upload.py` endpoint'leri: `POST /api/upload/presign`, `POST /api/upload/complete`
  (mevcut `UploadFile` kullanan endpoint'ler kaldırılır)
- [ ] `routers/stories.py`: `UploadFile` → presign/complete pattern
- [ ] `routers/messages.py`: media send → presign + `media/presign` + `media/complete`
- [ ] `routers/streams.py`: stream thumbnail upload → presign/complete
- [ ] `worker.py`: `process_media_upload` ARQ task ekle (FFmpeg + Pillow + WS notify)
- [ ] Alembic migration: `pending_uploads` tablosu
  (`upload_id UUID PK`, `user_id FK`, `key TEXT`, `context TEXT`, `status TEXT`, `expires_at TIMESTAMP`)
- [ ] `config.py`: `upload_presign_ttl: int = 900` ekle
- [ ] Mobile: tüm upload flow'larını 3-adım pattern'e güncelle
  **403 Expired URL — Transparent Retry zorunlu:** Adım 2 PUT'tan 403 dönerse kullanıcıya hata gösterme; arka planda sessizce yeni `/presign` çağrısı yap → yeni `put_url` al → PUT tekrarla (tek retry; ikinci 403'te kullanıcıya hata göster). TTL 900s, kullanıcı offline kalırsa URL süresi dolar.

### 0.4 Config Temizliği

- [ ] `config.py`: `site_url` hardcoded default kaldır
- [ ] `config.py`: `use_pgbouncer: bool = True` ekle
- [ ] `config.py`: `media_host`, `uploads_host` ekle — default yok (`""`), .env'de set edilmeli
- [ ] `config.py`: `minio_endpoint: str = "http://10.10.0.8:9000"` ekle — `presign_put()` için (orch_client override eder)
- [ ] `config.py`: `minio_endpoint_dm: str = "http://10.10.0.8:9000"` ekle — DM bucket presign için
- [ ] `config.py`: `ai_proxy_url: str` ekle — default `http://10.10.0.3:8001` (node2); uygulama her AI çağrısı öncesi orch redis'ten `ai_proxy:active_url` okur; key yoksa bu default kullanılır. Statik env değil — orchestrator failover'da bu key'i günceller.
- [ ] `config.py`: `edge_livekit_urls` default → `["http://10.10.0.1:7880", "http://10.10.0.6:7880"]` — orch_client.py 4. kademe hardcoded fallback (node1 + node4 WireGuard IP'leri); Redis ve guardian_state.json erişilemez olduğunda devreye girer
- [ ] `config.py`: `edge_minio_urls` default → `["http://10.10.0.8:9000", "http://10.10.0.12:9000"]` — orch_client.py 4. kademe hardcoded fallback (node7 + node8 WireGuard IP'leri); en sağlam DC'ler olarak seçilmiştir

### 0.5 Node Template Dosyaları

```
deploy/scale/V2.0/
  gateway1/resources/.env.production.template
  gateway2/resources/.env.production.template
  node1/resources/.env.production.template
  node2/resources/.env.production.template
  node3/resources/.env.staging.template      ← staging; .env.staging olarak kurulur
  node4/resources/.env.production.template
  node5/resources/.env.production.template
  node6/resources/.env.production.template
  node7/resources/.env.production.template
  node8/resources/.env.production.template
  node9/resources/.env.production.template
```

- [ ] Tüm template dosyalarını `<placeholder>` değerleriyle repoya commit et (§0.0 secret'larıyla doldurulmaz — sadece template)

**node5 + node6 `.env` içeriği (ortak):**
```env
# === Veritabanı & Cache ===
DATABASE_URL=postgresql+asyncpg://teqlif:<teqlif_db_password>@10.10.0.10:6432/teqlif
REDIS_URL=redis://:<core_redis_pass>@10.10.0.11:6379/0
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
USE_PGBOUNCER=True

# === MinIO ===
MEDIA_HOST=https://media.teqlif.com
UPLOADS_HOST=https://uploads.teqlif.com
MINIO_BUCKET=teqlif
MINIO_DM_BUCKET=teqlif-dm
MINIO_ENDPOINT=http://10.10.0.8:9000
MINIO_ENDPOINT_DM=http://10.10.0.8:9000
MINIO_ACCESS_KEY=<minio_root_user>
MINIO_SECRET_KEY=<minio_root_password>
MINIO_SECURE=False
MINIO_REGION=us-east-1

# === ClickHouse ===
CLICKHOUSE_HOST=10.10.0.13
CLICKHOUSE_PORT=8123
CLICKHOUSE_DB=teqlif_prod_analytics
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>

# === Guardian / Orchestrator ===
EDGE_NODE_ID=node5                   # node6 için: node6
DATA_DISK_PATH=/
DATA_SOURCE_NAME=postgresql://teqlif:<teqlif_db_password>@127.0.0.1:5432/teqlif?sslmode=disable

# === AI Proxy ===
AI_PROXY_URL=http://10.10.0.3:8001   # node2 default; orch redis'ten override edilir
AI_PROXY_INTERNAL_TOKEN=<ai_proxy_internal_token>

# === JWT / Auth ===
SECRET_KEY=<secret_key>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=43200

# === LiveKit ===
LIVEKIT_API_KEY=<livekit_api_key>
LIVEKIT_API_SECRET=<livekit_api_secret>

# === Firebase (FCM Push) ===
FIREBASE_SERVICE_ACCOUNT=/etc/teqlif/firebase-service-account.json

# === E-posta (Brevo) ===
BREVO_API_KEY=<brevo_api_key>
BREVO_SENDER_EMAIL=noreply@teqlif.com
BREVO_SENDER_NAME=teqlif

# === Apple Push (APNS VoIP) ===
APNS_KEY_PATH=/etc/teqlif/AuthKey_<apns_key_id>.p8
APNS_KEY_ID=<apns_key_id>
APNS_TEAM_ID=<apns_team_id>
IOS_BUNDLE_ID=teqlif
APNS_USE_SANDBOX=False

# === Google OAuth ===
GOOGLE_CLIENT_ID=<google_client_id>

# === Sentry ===
SENTRY_BACKEND_DSN=<sentry_backend_dsn>

# === Captcha (Cloudflare Turnstile) ===
CAPTCHA_ENABLED=True
CAPTCHA_PROVIDER=turnstile
CAPTCHA_SECRET_KEY=<captcha_secret_key>

# === Admin ===
ADMIN_EMAIL=<admin_email>
ADMIN_PASSWORD_HASH=<admin_password_hash>

# === Telegram (Ops Bildirim) ===
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID=<telegram_chat_id>

# === Genel ===
SITE_URL=https://www.teqlif.com
DEBUG=False
WEB_APP_ENABLED=False
```

`DATABASE_URL` → PG VIP `10.10.0.10` üzerinden PgBouncer port `6432`.

**ClickHouse erişim notu:** ClickHouse node9'da çalışır (10.10.0.13:8123). Her node (node5, node6) WireGuard üzerinden node9'a bağlanır. node9 down olduğunda analytics yazmaları ve sorguları circuit breaker ile sessizce düşer — analytics non-critical, app çalışmaya devam eder.

**node7 + node8 `.env` içeriği (özdeş — sadece EDGE_NODE_ID farklı):**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node7                  # node8 için: node8
DATA_DISK_PATH=/mnt/data
MINIO_VOLUMES=/mnt/data/minio
MINIO_ROOT_USER=<placeholder>
MINIO_ROOT_PASSWORD=<placeholder>
# GOMEMLIMIT, GOGC, MINIO_API_REQUESTS_MAX systemd unit'te Environment= ile set edilir
```

**node1 + node4 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node1                  # node4 için: node4
LIVEKIT_API_KEY=<placeholder>
LIVEKIT_API_SECRET=<placeholder>
DATA_DISK_PATH=/
```

**node2 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node2
AI_PROXY_INTERNAL_TOKEN=<ai_proxy_internal_token>
GROQ_API_KEY=<groq_api_key>
GEMINI_API_KEY=<gemini_api_key>
DATA_DISK_PATH=/
```

**node3 `.env.staging` içeriği** (`.env.staging.template` → `/etc/teqlif/.env.staging`; guardian drop-in bkz. §11.5):
```env
# === Veritabanı & Cache (lokal — node3 izole) ===
DATABASE_URL=postgresql+asyncpg://teqlif:<staging_pg_pass>@127.0.0.1:5432/teqlif_staging
REDIS_URL=redis://:<staging_redis_pass>@127.0.0.1:6379/0
ORCH_REDIS_URL=redis://:<staging_redis_pass>@127.0.0.1:6379/2
GUARDIAN_REDIS_URL=redis://:<staging_redis_pass>@127.0.0.1:6379/3
USE_PGBOUNCER=False

# === MinIO (lokal — node3 izole) ===
MEDIA_HOST=https://media-staging.teqlif.com
UPLOADS_HOST=https://uploads-staging.teqlif.com
MINIO_BUCKET=teqlif-staging
MINIO_DM_BUCKET=teqlif-dm-staging
MINIO_ENDPOINT=http://127.0.0.1:9000
MINIO_ENDPOINT_DM=http://127.0.0.1:9000
MINIO_ACCESS_KEY=<minio_staging_root_user>
MINIO_SECRET_KEY=<minio_staging_root_password>
MINIO_ROOT_USER=<minio_staging_root_user>
MINIO_ROOT_PASSWORD=<minio_staging_root_password>
MINIO_VOLUMES=/var/lib/minio-staging
MINIO_SECURE=False
MINIO_REGION=us-east-1

# === ClickHouse (devre dışı — 3.8GB RAM) ===
CLICKHOUSE_ENABLED=False
CLICKHOUSE_HOST=

# === Guardian / Orchestrator ===
EDGE_NODE_ID=node3
DATA_DISK_PATH=/

# === AI Proxy (lokal) ===
AI_PROXY_URL=http://127.0.0.1:8001
AI_PROXY_INTERNAL_TOKEN=<ai_proxy_internal_token>
GROQ_API_KEY=<groq_api_key>
GEMINI_API_KEY=<gemini_api_key>

# === JWT / Auth ===
SECRET_KEY=<staging_secret_key>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=43200

# === LiveKit (lokal — node3 izole) ===
LIVEKIT_URL=http://127.0.0.1:7880
LIVEKIT_API_KEY=<livekit_staging_api_key>
LIVEKIT_API_SECRET=<livekit_staging_api_secret>

# === Firebase (FCM Push) ===
FIREBASE_SERVICE_ACCOUNT=/etc/teqlif/firebase-service-account.json

# === E-posta (Brevo) ===
BREVO_API_KEY=<brevo_api_key>
BREVO_SENDER_EMAIL=noreply@teqlif.com
BREVO_SENDER_NAME=teqlif

# === Apple Push (APNS VoIP — sandbox) ===
APNS_KEY_PATH=/etc/teqlif/AuthKey_<apns_key_id>.p8
APNS_KEY_ID=<apns_key_id>
APNS_TEAM_ID=<apns_team_id>
IOS_BUNDLE_ID=teqlif
APNS_USE_SANDBOX=True

# === Google OAuth ===
GOOGLE_CLIENT_ID=<google_client_id>

# === Sentry ===
SENTRY_BACKEND_DSN=<sentry_backend_dsn_staging>

# === Captcha ===
CAPTCHA_ENABLED=False

# === Admin ===
ADMIN_EMAIL=<admin_email>
ADMIN_PASSWORD_HASH=<admin_password_hash>

# === Telegram ===
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID=<telegram_chat_id>

# === Genel ===
SITE_URL=https://staging.teqlif.com
DEBUG=False
WEB_APP_ENABLED=True
```

**gateway1 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=gateway1
DATA_DISK_PATH=/
```

**gateway2 `.env` içeriği** (gateway1 ile aynı yapı; `INTERFACE_SPEED_MBPS=4000` değeri `node.conf`'ta tanımlanır — bkz. §1.4):**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=gateway2
DATA_DISK_PATH=/
```

**node9 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<orch_redis_pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node9
DATA_DISK_PATH=/data
# ClickHouse — node9 üzerinde lokal
CLICKHOUSE_HOST=127.0.0.1
CLICKHOUSE_PORT=8123
CLICKHOUSE_DB=teqlif_prod_analytics
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>
# Backup scriptleri (Faz 10.6)
CORE_REDIS_PASS=<core_redis_pass>
PG_PASSWORD=<teqlif_db_password>
REPLICATOR_PASSWORD=<replicator_password>
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID=<telegram_chat_id>
```

### 0.6 Guardian Koordinatör — `backend/app/guardian/`

Guardian koordinatör, **seçilmiş lider node'da** `teqlif-guardian.service` içinden otomatik olarak aktif olan global karar motoru. Keepalived MASTER olmak zorunda değil — `guardian_priority` ile seçilen herhangi bir node lider olabilir. Sistem 1 node'da da 10 node'da da aynı kod çalışır.

#### Veri Modeli — Guardian Redis (port 6382)

```
# ── Topology Registry ─────────────────────────────────────────────────
guardian:topology:{node_id}           Hash  TTL=60s (agent her 30s yeniler)
  node_id, env, guardian_priority
  public_ip, wg_ip, guardian_port, speed_mbps
  cpu_cores, ram_gb
  components   → JSON  [{"name":"minio","env":"production","role":"storage_primary",...}]
  registered_at

guardian:components:{name}:{env}      Set   → bu component:env'i çalıştıran node_id'ler
  örn. guardian:components:minio:production = {"node7","node8"}
       guardian:components:livekit:production = {"node1","node4"}
       guardian:components:teqlif:staging     = {"node3"}

guardian:role:{role}                  Set   → bu rolü üstlenen node_id'ler
  örn. guardian:role:storage_primary = {"node7","node8"}
       guardian:role:ai_proxy_fallback = {"node3"}

guardian:env:production               Set   → production component'i olan node_id'ler
guardian:env:staging                  Set   → staging component'i olan node_id'ler

# ── Service State (component bazlı, env bazlı) ────────────────────────
guardian:service:{name}:{env}         Hash
  state     → HEALTHY | DEGRADED | DOWN
  # HEALTHY: ≥1 capable node sağlıklı
  # DEGRADED: kısmi kapasite (örn. 2 storage'dan 1'i kaldı)
  # DOWN: 0 capable node — sistem o servisi veremez; alert gönderildi, bekleniyor
  alive_nodes   → JSON list (sağlıklı node'lar)
  degraded_since → unix ts (DEGRADED/DOWN olduğu an)
  last_healthy   → unix ts

# ── Job State Machine ──────────────────────────────────────────────────
guardian:job:{job_id}                 Hash
  type      → backup_postgres | backup_clickhouse | backup_redis | offsite_sync |
               failover_storage | failover_ai | failover_gateway |
               failover_core | stream_rebalance | service_heal | storage_rebalance
  state     → PENDING | RUNNING | INTERRUPTED | RESUMING | SUCCESS | FAILED | DEAD
  env       → production | staging (hangi ortam için)
  assigned  → node_id (yürüten node)
  trigger   → "scheduled" | "node_down:node7" | "service_down:minio:production" | "manual"
  checkpoint → JSON (kaldığı yer — interrupt → resume buradan)
  retry     → int
  max_retry → 3
  started_at, updated_at

guardian:jobs:active                  Set   → aktif job_id'ler
guardian:jobs:history                 ZSet  score=ts → son 500 iş

# ── Event Stream ──────────────────────────────────────────────────────
guardian:events                       Redis Stream (XADD — persistent, ordered)
  {type, node, component, env, severity, message, job_id, ts}
  severity: info | warn | alert | critical

# ── Local State Cache ─────────────────────────────────────────────────
# Lider her 30s tüm node'lara gönderir → /var/lib/teqlif/guardian_state.json
# Guardian redis ve lider erişilemez olsa bile uygulama bu dosyayı okur
{
  "schema_version": 1,
  "updated_at": 0,
  "leader": "node5",
  "routing": {
    "storage_nodes": [],        # → orch:routing:storage_nodes ile sync
    "stream_primary": "",       # → orch:routing:stream_primary
    "stream_backup": "",        # → orch:routing:stream_backup
    "ai_proxy_url": "",         # → orch:routing:ai_proxy_url
    "gateways": []              # → orch:routing:gateways
  },
  "service_states": {},         # guardian:service:* snapshot
  "system_state": "healthy"
}

# ── Komut Kanalları ───────────────────────────────────────────────────
guardian:cmd:{node_id}                PubSub → edge agent command executor dinler
guardian:cmd_result:{node_id}         Stream → komut sonucu (agent yazar, koordinatör okur)

# ── Backup Registry ───────────────────────────────────────────────────
guardian:backup:{type}:last_ok        String → unix ts (backup script tamamlandığında yazar)
guardian:backup:{type}:job            String → aktif job_id
```

#### Modül Yapısı — `backend/app/guardian/`

```
guardian/
  main.py           ← guardian_loop() — lider seçildiyse koordinatörü başlat
  election.py       ← Redis NX (hızlı) + UDP peer (yavaş) lider seçimi
  topology.py       ← guardian:topology:* yönetimi; component/role index güncelleme
  health_monitor.py ← edge:metrics + edge:health TTL izle; service state hesapla
  state_machine.py  ← HEALTHY/DEGRADED/DOWN geçişleri; event yayını
  job_manager.py    ← Job CRUD, checkpoint, retry, resume mantığı
  playbook_runner.py← playbook başlat, adım yürüt, interrupt/resume
  state_broadcaster.py ← guardian_state.json'u tüm node'lara gönder (her 30s)
                          ZORUNLU: atomik yazma — tmp dosyaya yaz → rename (os.replace)
                          Yarım JSON bırakmaz; uygulama her zaman tutarlı dosya okur
  routing/
    storage.py      ← role:storage_primary node'larından sağlıklı olanlar
    stream.py       ← stream_score (net_out_percent*0.4+cpu*0.3+ram*0.3) en düşük
    ai_proxy.py     ← ai_proxy_primary → fallback → last_resort öncelik zinciri
    gateway.py      ← gateway health; CF DNS Multi-A için alive list
  playbooks/
    node_down.py    ← component bazlı: StorageDown, GatewayDown, AIProxyDown, CoreDown
    service_heal.py ← node ayakta + servis bozuk → reset-failed + start
    recovery.py     ← node/servis geri gelince reverse işlemler; routing'e yeniden ekle
    backup.py       ← BackupJob checkpoint'li; kesilirse resume
  dns.py            ← CF API: gateway + storage DNS Multi-A yönetimi
  alerting.py       ← severity bazlı Telegram #ops (warn/info) / #alerts (critical)
  backup_monitor.py ← guardian:backup:*:last_ok freshness; eşik aşılınca alert + trigger
  edge.py           ← guardian:cmd:{node} pub/sub; cmd_result oku
  models.py         ← NodeState, ServiceState, Job, PlaybookContext, RoutingDecision dataclass
```

#### Koordinatör Ana Döngüsü (lider node'da)

```python
# guardian/main.py — sadece lider seçilmişse çalışır

async def coordinator_loop():
    # UDP fallback modunda koordinatör çalışmaz — Redis gerektiren hiçbir işlem yapılamaz
    if election.mode == "udp":
        await alerting.critical(
            "guardian-redis erişilemez — UDP fallback lider; koordinatör pasif. Manuel müdahale gerekebilir."
        )
        return  # bir sonraki election tick'inde yeniden değerlendirilir

    while True:
        # 1. Topology refresh — stale node'ları çıkar
        await topology.refresh()                    # guardian:topology:* TTL kontrol

        # 2. Tüm service state'leri hesapla (component bazlı, env bazlı)
        await health_monitor.compute_service_states()
        # guardian:service:minio:production → HEALTHY/DEGRADED/DOWN

        # 3. Service state değişimi → playbook tetikle
        await state_machine.process_transitions()
        # minio:production DOWN → StorageNodeDownPlaybook başlat
        # minio:production DOWN→HEALTHY → RecoveryPlaybook başlat

        # 4. Routing kararları → orch-redis'e yaz (uygulama okur)
        await routing.update_all()

        # 5. Aktif job'ları tick et (INTERRUPTED → RESUMING)
        await job_manager.tick()

        # 6. Backup freshness kontrol
        await backup_monitor.check_all()

        # 7. DNS senkronizasyonu
        await dns.sync_if_changed()

        # 8. State.json broadcast (her 30s)
        await state_broadcaster.push_if_due()

        await asyncio.sleep(3)
```

#### Routing Eligibility Kuralı

Guardian bir componenti routing havuzuna **ancak dört şart birlikte sağlandığında** alır:

```
1. node.conf'ta traffic_eligible: true         ← insan onayı; default false
2. env eşleşmesi: production routing → sadece env=production component
3. systemd unit: active (systemctl is-active)
4. health_check: ok (HTTP 200 veya cmd exit 0)

Dördü de sağlanmadan → component izlenir, alert atılır, AMA routing yapılmaz.
```

```python
# guardian/topology.py — eligibility check
def is_routing_eligible(component: dict, target_env: str) -> bool:
    return (
        component.get("traffic_eligible", False)   # explicit human approval
        and component["env"] == target_env          # env must match
        # systemd + health checks: health_monitor'dan gelir
    )
```

Bu kural şunu engeller: node3'te developer staging için LiveKit başlattı → Guardian production routing'ine dahil etmez. Ya da node9 kuruldu ama `traffic_eligible` yazılmadı → Guardian izler ama trafik göndermez.

**Desired state kalıcılığı:** Guardian `traffic_eligible` alanını ASLA otomatik değiştirmez — bu yalnızca insan onayı gerektirir. Guardian'ın routing kararları (hangi node'a trafik yönlensin) `orch:routing:*` key'lerine yazılır; bu key'ler orch-redis'te tutulur (Keepalived HA, VIP 10.10.0.11:6379). Node reboot sonrasında guardian agent `traffic_eligible: true` olan node.conf'unu Redis'e yeniden push eder — eligibility değişmez. orch-redis routing key'leri bağımsız persist eder. Bu nedenle node.conf'un disk'te manuel güncellenmesi gereksinimi yoktur.

#### Playbook — Component Bazlı, Env-Aware

```python
# guardian/playbooks/node_down.py

class ComponentDownPlaybook:
    """Hangi node değil — hangi component:env down oldu?"""

    HANDLERS = {
        "minio:production":           StorageFailoverHandler,
        "livekit:production":         StreamRebalanceHandler,
        "teqlif-ai-proxy:production": AIProxyFailoverHandler,
        "nginx:production":           GatewayFailoverHandler,
        "teqlif:production":          CoreAppCrashHandler,
        # staging'deki bir servis düşerse: ayrı handler, prod'u etkilemez
        "teqlif:staging":             StagingDownHandler,
    }

    async def run(self, component_name, env, ctx: PlaybookContext):
        key = f"{component_name}:{env}"
        handler = self.HANDLERS.get(key)
        if handler:
            await handler(ctx).run()
        else:
            # Tanınmayan component → sadece alert; kod değişikliği gerekmez
            await ctx.alert(f"unknown component down: {key}", severity="warn")
```

- [ ] Keepalived `notify_master/backup` scriptleri güncelle: `teqlif-orchestrator` → `teqlif-guardian` (guardian tüm node'larda her zaman çalışır; scriptler guardian'ı durdurmaz/başlatmaz — yalnızca teqlif, teqlif-worker, pgbouncer, PG, Redis yönetir)

### 0.7 Ops Komutları

- [ ] `scripts/teqlif-restart.sh`: WireGuard IP → rol tespiti → uygun servisleri yeniden başlat
- [ ] `scripts/teqlif-refresh.sh`: git pull + sync (veri servislerine dokunmaz)
- [ ] Her iki script: node8 = `10.10.0.12` = storage olarak tanısın
- [ ] `deploy/scale/V2.0/node.conf.example`: tüm roller için örnek şablon

### 0.8 Güvenlik Düzeltmesi

- [ ] FastAPI `--forwarded-allow-ips 10.10.0.2,10.10.0.9` (gateway1 + gateway2 WG IP'leri)

### 0.9 Doğrulama (lokalde)

```bash
python -c "from app.config import settings; print(settings.model_fields.keys())"
grep -r "edge_orchestrator" backend/app/  # → 0 sonuç
grep -r "minio_storage_quota" backend/app/  # → 0 sonuç
dart analyze mobile/  # → 0 hata
```

---

### 0.10 Cloudflare Güvenlik Yapılandırması (Free Tier)

Bu adımlar VPS'e dokunmaz — Cloudflare Dashboard'da yapılır.

**SSL/TLS (Dashboard → SSL/TLS):**
- [ ] Mode → **Full (Strict)** — Origin Certificate zorunlu; "Flexible" MITM riski taşır
- [ ] HSTS → **Enable** (max-age 6 months, includeSubDomains) — CF edge'de header eklenir, nginx'e gerek kalmaz
- [ ] Minimum TLS Version → **TLS 1.2**

**Güvenlik (Dashboard → Security → Settings):**
- [ ] Security Level → **Low** — Medium/High JS challenge üretir; Flutter dart:io native HTTP client JS çözemez → 503/403; "Low" yalnızca en yüksek tehdit puanlı IP'leri bloklar
- [ ] Bot Fight Mode → **Etkinleştirme** ⚠️ — Free tier Bot Fight Mode non-browser UA'leri JS challenge'a sokar; `Dart/<ver> (dart:io)` taşıyan tüm mobil API istekleri bloklanır
- [ ] Browser Integrity Check → **Etkinleştirme** ⚠️ — Browser-tipik header eksikliğinde challenge üretir; native app trafiği Referer header taşımaz → bloklanabilir

**IP Access Rules — unlimited, 5 WAF kuralı harcanmaz (Security → WAF → IP Access Rules):**
- [ ] Tor → **Block** (CF ayrı kategori sunuyor)
- [ ] Bilinen tarayıcı ASN'leri → **Block** (örn. Shodan AS12876, Censys AS396982)
- [ ] Uygulama ülke dışı kullanımı yoksa: hizmet verilen ülkeler dışı → **Managed Challenge**

**WAF Custom Rules — 5 kuralı optimum dağıt (Security → WAF → Custom Rules):**

```
Kural 1 — Path Traversal + SQL Injection imzası (Block):
(http.request.uri.path contains "../" or
 http.request.uri.path contains "/etc/passwd" or
 http.request.uri.query contains "UNION SELECT" or
 http.request.uri.query contains "<script")

Kural 2 — Kötü niyetli tarayıcı parmak izi (Block):
(lower(http.user_agent) contains "sqlmap" or
 lower(http.user_agent) contains "nikto" or
 lower(http.user_agent) contains "masscan" or
 lower(http.user_agent) contains "zgrab" or
 lower(http.user_agent) contains "nuclei" or
 http.user_agent eq "")

Kural 3 — API auth endpoint'lerine yüksek tehdit skoru (Managed Challenge):
(http.request.uri.path contains "/api/auth" and cf.threat_score gt 15)

Kural 4 — Upload endpoint POST flood (JS Challenge):
(http.request.method eq "POST" and
 http.request.uri.path contains "/api/" and
 cf.threat_score gt 20)

Kural 5 — Header anomalisi (Managed Challenge):
(not http.request.headers["user-agent"][0] exists or
 http.request.headers["x-forwarded-for"][0] matches "^[0-9,. ]{50,}")
```

**Cache Rules — 4 Page Rule (Rules → Page Rules):**
- [ ] `media.teqlif.com/*` → Cache Level: **Cache Everything** + Edge TTL: 1 month ← MinIO public media; CF edge'de cache'lenir, HDD okuma yükü azalır
- [ ] `uploads.teqlif.com/*` → Cache Level: **Bypass** ← Presigned URL S3 imzası CF proxy'den geçerse bozulur; DM yanıtları kullanıcıya özel (DNS Only olsa da Bypass kural eklenir — ileride Proxied'a geçilirse koruma)
- [ ] `api.teqlif.com/api/*` → Cache Level: **Bypass** (API yanıtları cache'lenmemeli)
- [ ] `*.teqlif.com/*.min.js` → Cache Level: **Cache Everything** + Browser TTL: 1 year

---

### 0.11 Mobil Kod Değişiklikleri

- [ ] `mobile/lib/services/image_cache_manager.dart`:
  `stalePeriod: Duration(days: 2)` → `Duration(days: 14)` (§15.10 kararı)
- [ ] `mobile/lib/services/video_cache_manager.dart`:
  `getTemporaryDirectory()` → `getApplicationSupportDirectory()` (OS tarafından rastgele silinmez)
- [ ] Logout akışı: `CacheService.clearData()` + `VideoCacheManager.instance.updateCache({}, {})` çağrıları ekle (DM içerikleri kullanıcıya bağlı — çıkışta silinmeli)
- [ ] `mobile/lib/core/config/app_config.dart` V2.0:
  - `mediaBaseUrl` türetme (`replaceAll`) kaldır
  - `uploadsHost`, `mediaHost`, `shareBaseUrl`, `captchaBaseUrl` alanları ekle
  - Tüm değerleri `String.fromEnvironment(...)` ile oku
- [ ] `mobile/lib/services/captcha_service.dart`: hardcoded `'https://www.teqlif.com'` → `appConfig.captchaBaseUrl`
- [ ] Hardcoded share URL'leri (listing, profil, yayin, pro-plan, support, kvkk — 14 nokta) → `appConfig.shareBaseUrl`
- [ ] `dart_defines/staging.json` + `release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` ekle
- [ ] Backend: `MessageOut.cache_key: Optional[str]` şema alanı ekle; `GetMessagesQuery._presign_if_dm()` hem `url` (pre-signed) hem `cache_key` (sabit S3 path) döndürsün
- [ ] Mobile: DM medya cache key olarak `msg['media_url']` değil `msg['media_cache_key']` kullan
  **CachedNetworkImage zorunlu parametre:** `CachedNetworkImage(imageUrl: signedUrl, cacheKey: msg.mediaCacheKey)` — `cacheKey` eksik bırakılırsa widget imzalı URL'in tamamını (değişen query param'larıyla) cache key alır; her yeni presign'da cache miss → her 15 dakikada yeniden indirme; 14 günlük `stalePeriod` tasarımı çöker
- [ ] `frontend/.well-known/assetlinks.json` oluştur (Android App Links desteği)
- [ ] `frontend/.well-known/apple-app-site-association` oluştur (iOS Universal Links desteği)
  - `DeepLinkService` `https://www.teqlif.com/...` linklerini iOS'ta universal link olarak yakalar
  - `www.teqlif.com/.well-known/apple-app-site-association` → nginx statik dosya olarak serve eder
  - `Content-Type: application/json` header zorunlu

---

## Faz 1 — OS Temeli (Tüm Node'lar)

**Her node için — sırayla veya paralel uygulanır.**

### 1.1 Temel Paketler

```bash
apt-get update && apt-get upgrade -y
apt-get install -y \
  curl wget git \
  ufw fail2ban \
  wireguard wireguard-tools \
  chrony \
  htop iotop nethogs \
  unattended-upgrades apt-listchanges \
  rsync logrotate \
  jq \
  python3 python3-pip python3-venv python3-dev \
  build-essential
```

### 1.2 Kullanıcı ve SSH

```bash
# Kullanıcı oluştur
adduser tucibeyin
usermod -aG sudo tucibeyin

# SSH key ekle
mkdir -p /home/tucibeyin/.ssh
echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
chmod 700 /home/tucibeyin/.ssh
chmod 600 /home/tucibeyin/.ssh/authorized_keys
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
```

`/etc/ssh/sshd_config` → değiştirilecek satırlar:
```
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
X11Forwarding no
AllowUsers tucibeyin
```

```bash
systemctl restart sshd
```

### 1.3 Dizin Yapısı

```bash
mkdir -p /var/www/teqlif.com
mkdir -p /etc/teqlif
mkdir -p /var/lib/teqlif
mkdir -p /var/log/teqlif/{api,worker,orchestrator}
chown -R tucibeyin:tucibeyin /var/www/teqlif.com /var/log/teqlif /var/lib/teqlif
chmod 755 /var/log/teqlif   # 755: promtail (system user) log dizinine girebilmeli; dosyalar systemd tarafından 0644 oluşturulur
```

### 1.4 /etc/teqlif/node.conf

YAML formatında — Guardian agent başlangıçta okur. Her node kendini tam olarak tanımlar; orchestrator/guardian bu dosyayı okuyarak topolojiyi keşfeder, hardcoded bilgiye ihtiyaç duymaz.

```bash
apt-get install -y python3-yaml   # guardian_agent.py için (1.1'de eklenmemişse)
```

**Şema (her node'a uygun değerlerle doldurulur):**

```yaml
# /etc/teqlif/node.conf
# ── Kimlik ────────────────────────────────────────────────────────────
node_id: node5                  # benzersiz, değişmez
env: production                 # production | staging | hybrid

# ── Guardian lider önceliği ───────────────────────────────────────────
# Yüksek olan önce lider adayı olur. Tüm node'lar reachable ise en yüksek kazanır.
# Önerilen: node5=100, node6=90, node3=80, node1=70, node4=60,
#            node2=50, gateway1=40, gateway2=30, node7=20, node8=10, node9=5
# node9 kasıtlı düşük: backup/monitor rolü; asla guardian lideri olmamalı
guardian_priority: 100

# ── Ağ ───────────────────────────────────────────────────────────────
network:
  public_ip: <node5_public_ip>
  wg_ip: 10.10.0.5
  wg_port: 51820
  guardian_port: 9901          # UDP heartbeat — tüm node'larda aynı
  speed_mbps: 1000

# ── Donanım (sabit beyan — agent runtime'da live ölçer, burası referans) ──
hardware:
  cpu_cores: 4
  cpu_model: "AMD EPYC"
  ram_gb: 7.8
  disks:
    - mount: /
      size_gb: 49
      type: nvme
      role: system             # system | data | backup | cache

# ── Componentler ─────────────────────────────────────────────────────
# Her component için zorunlu alanlar:
#   name             → servis adı (teqlif, minio, livekit, redis-core, ...)
#   env              → production | staging
#                      NOT: node env=hybrid olabilir; component asla hybrid değildir.
#   systemd_unit     → systemctl ile yönetilen unit adı
#   role             → bu node'da bu componentin rolü (bkz. ROLE rehberi)
#
# İsteğe bağlı alanlar:
#   port             → dinlediği port (yoksa boş bırak)
#   health_check     → "http" veya "cmd" tipi sağlık kontrolü
#   autostart        → false: guardian komutu olmadan başlamaz (default: true)
#
# Trafik yapılandırması — SADECE insan yazar, guardian ASLA otomatik değiştirmez:
#
#   traffic_eligible → true: guardian bu componente trafik yönlendirebilir
#                      false veya YOK: guardian izler, alert atar ama routing YAPMAZ
#                      DEFAULT: false — hiç yazılmamışsa guardian trafiği göndermez
#                      KURAL: alive + eligible = routing; alive alone ≠ routing
#
#   traffic_type     → internal_mesh    : sadece WireGuard mesh içi erişim
#                                         (Redis, PG, ClickHouse — dış erişim yok)
#                      gateway_proxied  : gateway1/2 arkasında; dışarıdan direct erişim yok
#                                         (teqlif API, MinIO S3 API)
#                      direct_internet  : dışarıya açık port; client doğrudan bağlanır
#                                         (LiveKit, MinIO uploads endpoint, nginx/storage)
#
#   required_ports   → direct_internet componentler için: bu portlar açık olmalı
#                      Guardian bunu bilgiye yazar ama kontrol etmez — insan sorumlu
#
# ROLE rehberi:
#   db_primary / db_replica / db_pooler
#   cache_primary / cache_replica
#   orch_primary / orch_replica
#   guardian_primary / guardian_replica
#   api / worker / worker_critical
#   analytics
#   storage_primary / storage_fallback
#   stream_primary / stream_backup
#   ai_proxy_primary / ai_proxy_fallback / ai_proxy_last_resort
#   gateway / monitor / backup_coordinator

components:
  - name: postgresql
    env: production
    port: 5432
    systemd_unit: postgresql.service
    health_check:
      type: cmd
      cmd: "pg_isready -h 127.0.0.1 -p 5432 -q"
    role: db_primary
    traffic_eligible: true
    traffic_type: internal_mesh      # PG sadece mesh içi; dışarıya asla açılmaz

  - name: redis-core
    env: production
    port: 6379
    systemd_unit: redis-core.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6379 -a $CORE_REDIS_PASS --no-auth-warning ping"
    role: cache_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: redis-orch
    env: production
    port: 6380
    systemd_unit: redis-orch.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6380 -a $ORCH_REDIS_PASS --no-auth-warning ping"
    role: orch_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: redis-guardian
    env: production
    port: 6382
    systemd_unit: redis-guardian.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6382 -a $GUARDIAN_REDIS_PASS --no-auth-warning ping"
    role: guardian_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: pgbouncer
    env: production
    port: 6432
    systemd_unit: pgbouncer.service
    health_check:
      type: cmd
      cmd: "pg_isready -h 127.0.0.1 -p 6432 -q"
    role: db_pooler
    traffic_eligible: true
    traffic_type: internal_mesh

  # clickhouse → node9'a taşındı (bkz. §4.8 + Faz 13)

  - name: teqlif
    env: production
    port: 8000
    systemd_unit: teqlif.service
    health_check:
      type: http
      url: http://127.0.0.1:8000/health
    role: api
    traffic_eligible: true
    traffic_type: gateway_proxied    # gateway1/2 proxy'ler; dışarıdan direct erişim yok

  - name: teqlif-worker
    env: production
    systemd_unit: teqlif-worker.service
    role: worker
    traffic_eligible: false          # worker dışarıya trafik almaz; izleme için kayıt var

  - name: teqlif-worker-critical
    env: production
    systemd_unit: teqlif-worker-critical.service
    role: worker_critical
    traffic_eligible: false

  - name: teqlif-ai-proxy
    env: production
    port: 8001
    systemd_unit: teqlif-ai-proxy.service
    health_check:
      type: http
      url: http://10.10.0.5:8001/health
    role: ai_proxy_last_resort
    traffic_eligible: true
    traffic_type: internal_mesh      # AI proxy sadece mesh içi; API gateway üzerinden değil
    autostart: false                 # guardian start_service komutuyla başlar; boot'ta başlamaz
```

> **traffic_eligible kuralı:** Guardian bir node'da component adını tanısa bile `traffic_eligible: true` olmadan routing yapmaz. Bu alanı sadece insan yazar — component tam olarak konfigüre edilip, gerekli portlar açılıp, hazır olduğu doğrulandıktan sonra.
> **Component asla hybrid değildir:** `env: production` veya `env: staging` — ikisi aynı anda olamaz. Aynı node'da her ikisi de çalışabilir ama ayrı component girişleriyle (örn. hem `teqlif:production` hem `teqlif:staging`).
> **node.conf örnekleri** tüm roller için `deploy/scale/V2.0/node.conf.examples/` dizininde şablon olarak tutulur.

**node9 node.conf (monitor/backup/clickhouse rolü):**

```yaml
# /etc/teqlif/node.conf — node9
node_id: node9
env: production

# Kasıtlı düşük öncelik — backup/monitor, asla guardian lider adayı olmamalı
guardian_priority: 5

network:
  public_ip: <node9_public_ip>    # 135.125.223.43
  wg_ip: 10.10.0.13
  wg_port: 51820
  guardian_port: 9901
  speed_mbps: 480                 # YABS: ~480 Mbps outbound

hardware:
  cpu_cores: 8                    # Xeon D-2123IT 4c/8t
  cpu_model: "Intel Xeon D-2123IT"
  ram_gb: 31
  disks:
    - mount: /
      size_gb: 150
      type: hdd
      role: system
    - mount: /data
      size_gb: 3500
      type: hdd_raid1
      role: backup                # ClickHouse + WAL + backup

components:
  - name: clickhouse
    env: production
    port: 8123
    systemd_unit: clickhouse-server.service
    health_check:
      type: cmd
      cmd: "clickhouse-client --query='SELECT 1' 2>/dev/null"
    role: analytics
    traffic_eligible: true
    traffic_type: internal_mesh   # Sadece WG mesh; dış erişim yok

  - name: prometheus
    env: production
    port: 9090
    systemd_unit: prometheus.service
    health_check:
      type: http
      url: "http://127.0.0.1:9090/-/healthy"
    role: monitor
    traffic_eligible: false       # Monitoring araçları trafik routing'ine dahil değil

  - name: loki
    env: production
    port: 3100
    systemd_unit: loki.service
    health_check:
      type: http
      url: "http://127.0.0.1:3100/ready"
    role: monitor
    traffic_eligible: false

  - name: grafana
    env: production
    port: 3000
    systemd_unit: grafana-server.service
    health_check:
      type: http
      url: "http://127.0.0.1:3000/api/health"
    role: monitor
    traffic_eligible: false

  - name: teqlif-pg-receivewal
    env: production
    systemd_unit: teqlif-pg-receivewal.service
    health_check:
      type: cmd
      cmd: "systemctl is-active teqlif-pg-receivewal -q"
    role: backup_coordinator
    traffic_eligible: false
```

```bash
chmod 644 /etc/teqlif/node.conf
# guardian_agent.py okuma testi:
python3 -c "import yaml; c=yaml.safe_load(open('/etc/teqlif/node.conf')); print(c['node_id'], c['env'])"
```

### 1.5 fail2ban

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true

# nginx — gateway + storage node'larda anlamlı; diğerlerinde de zararı yok
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 5
findtime = 60
bantime  = 86400

[nginx-req-limit]
enabled  = true
filter   = nginx-req-limit
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 7200
```

```bash
# nginx-req-limit filtresi (fail2ban bunu bilmez, tanımla):
cat > /etc/fail2ban/filter.d/nginx-req-limit.conf << 'EOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
EOF

systemctl enable --now fail2ban
```

### 1.6 NTP + Timezone

```bash
timedatectl set-timezone UTC
systemctl enable --now chrony
chronyc tracking  # senkronize olduğunu doğrula
```

### 1.7 Otomatik Güvenlik Güncellemeleri

```bash
dpkg-reconfigure -plow unattended-upgrades
# Sadece security güncellemeleri aktif; reboot: kapalı (manual kontrol)
```

### 1.8 LimitNOFILE — Sistem Geneli

```ini
# /etc/security/limits.d/teqlif.conf
tucibeyin soft nofile 65535
tucibeyin hard nofile 65535
root      soft nofile 65535
root      hard nofile 65535
```

```ini
# /etc/systemd/system.conf (ve /etc/systemd/user.conf)
DefaultLimitNOFILE=65535
```

```bash
systemctl daemon-reload
```

### 1.9 Swap Dosyası (Core + Storage node'ları)

Core node'lar (node5: 7.8 GB RAM, 49 GB NVMe) ve storage node'lar (node7/8: 2.9 GB RAM, 2 GB swap önceden mevcut olabilir):

```bash
# Mevcut swap kontrolü:
swapon --show
# Swap yoksa oluştur (core node'lar için 8 GB — NVMe üzerinde düşük gecikme):
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
# Doğrula:
free -h | grep Swap
```

Storage node'larda kurulum sırasında 2 GB swap bölümü genellikle var; yoksa aynı adımlarla 2 GB swapfile oluştur.

### 1.10 Log Rotation — Teqlif Servisleri

```bash
cat > /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/**/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
# Test:
logrotate -d /etc/logrotate.d/teqlif
```

`copytruncate` kullanılır — `Restart=` tetiklemeden log dosyasını döndürür; `append:` ile açık log handle'ları kırılmaz.

### 1.11 Audit Logging (auditd)

```bash
apt-get install -y auditd

# Kritik dosya ve komutları izle:
cat > /etc/audit/rules.d/teqlif.rules << 'EOF'
-w /etc/teqlif/          -p wa -k teqlif_secrets
-w /etc/wireguard/       -p wa -k wireguard_config
-w /home/tucibeyin/.ssh/ -p wa -k ssh_keys
-w /etc/sudoers          -p wa -k sudoers_change
-w /bin/sudo             -p x  -k sudo_exec
-a always,exit -F arch=b64 -S execve -F uid=0 -k root_commands
EOF

systemctl enable --now auditd
# Doğrulama:
auditctl -l | wc -l  # kural sayısı > 0 olmalı
```

Log okuma: `ausearch -k teqlif_secrets -i | tail -20`

### 1.12 Transparent Hugepages Kapatma (Tüm Node'lar)

Kernel varsayılanı THP açık gelir. Redis startup'ta doğrudan uyarır; PostgreSQL write amplification yaşar. Kalıcı kapatma:

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/thp-disable.service \
   /etc/systemd/system/thp-disable.service
systemctl daemon-reload
systemctl enable thp-disable.service

# Doğrula:
cat /sys/kernel/mm/transparent_hugepage/enabled
# → always madvise [never]
```

### 1.13 Doğrulama

```bash
ssh -o PasswordAuthentication=no tucibeyin@<node_ip>  # root girişi reddedilmeli
chronyc tracking | grep "System time"
free -h | grep Swap   # swap aktif görünmeli
```

---

## Faz 2 — WireGuard Mesh (Tüm Node'lar)

**Önkoşul:** Faz 1 tüm node'larda tamamlandı.

### 2.1 Anahtar Üretimi — Her Node'da Ayrı Ayrı

```bash
# Her node'da VPS üzerinde çalıştır — private key ASLA repoya gitmiyor:
cd /etc/wireguard
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/pubkey
chmod 600 /etc/wireguard/privatekey
```

Pubkey'i not et — tüm node'ların birbirini tanıması için gerekli.

### 2.2 wg0.conf Yapısı

WireGuard sadece `AllowedIPs`'de tanımlı adresler için trafik yönlendirir. Keepalived VIP'leri (`10.10.0.10`, `10.10.0.11`) edge node'lar tarafından erişilmesi gerektiğinden (ORCH_REDIS_URL, DATABASE_URL), bu VIP'ler **node5'in peer kaydına** eklenmeli.

**Kural:**
- **Tüm node'larda** `[Interface]` bloğunda `MTU = 1420` — WireGuard IPv4 overhead 60 byte; 1500-60=1440, güvenli değer 1420. Ayarlanmazsa cloud provider'lar arası büyük transferlerde fragmentation yaşanabilir.
- **Tüm non-core node'larda** (gateway1/2, node1/2/3/4/7/8): node5 peer'ında VIP'ler var, node6'da yok (node5 = başlangıçta primary)
- **node5'in kendi wg0.conf'unda**: node6 peer'ında VIP yok
- **node6'nın kendi wg0.conf'unda**: node5 peer'ında VIP'ler var (node6 de önce node5'e bağlanır)
- Failover olduğunda: `wg set` + wg0.conf güncellenmesi gerekir (→ §4.5 notify_master scripti)

**Tüm non-core node'lar için örnek — node7'nin wg0.conf:**
```ini
# /etc/wireguard/wg0.conf — node7 örneği (non-core node'lar için şablon)
# chmod 600 /etc/wireguard/wg0.conf  ← ZORUNLU

[Interface]
Address = 10.10.0.8/24
ListenPort = 51820
MTU = 1420
PrivateKey = <node7_private_key>

# gateway1
[Peer]
PublicKey = <gateway1_pubkey>
AllowedIPs = 10.10.0.2/32
Endpoint = <gateway1_public_ip>:51820
PersistentKeepalive = 25

# gateway2
[Peer]
PublicKey = <gateway2_pubkey>
AllowedIPs = 10.10.0.9/32
Endpoint = <gateway2_public_ip>:51820
PersistentKeepalive = 25

# node1
[Peer]
PublicKey = <node1_pubkey>
AllowedIPs = 10.10.0.1/32
Endpoint = <node1_public_ip>:51820
PersistentKeepalive = 25

# node2
[Peer]
PublicKey = <node2_pubkey>
AllowedIPs = 10.10.0.3/32
Endpoint = <node2_public_ip>:51820
PersistentKeepalive = 25

# node3
[Peer]
PublicKey = <node3_pubkey>
AllowedIPs = 10.10.0.4/32
Endpoint = <node3_public_ip>:51820
PersistentKeepalive = 25

# node4
[Peer]
PublicKey = <node4_pubkey>
AllowedIPs = 10.10.0.6/32
Endpoint = <node4_public_ip>:51820
PersistentKeepalive = 25

# node5 — PRIMARY CORE: direkt IP + iki Keepalived VIP
[Peer]
PublicKey = <node5_pubkey>
AllowedIPs = 10.10.0.5/32, 10.10.0.10/32, 10.10.0.11/32
Endpoint = <node5_public_ip>:51820
PersistentKeepalive = 25

# node6 — STANDBY CORE: sadece direkt IP (başlangıçta VIP yok)
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node8 (node7 için)
[Peer]
PublicKey = <node8_pubkey>
AllowedIPs = 10.10.0.12/32
Endpoint = <node8_public_ip>:51820
PersistentKeepalive = 25

# node9 — Backup + Monitor + ClickHouse (OVH LIM)
[Peer]
PublicKey = <node9_pubkey>
AllowedIPs = 10.10.0.13/32
Endpoint = <node9_public_ip>:51820
PersistentKeepalive = 25
```

**node5'in kendi wg0.conf'u** — node6 peer'ında VIP yok, diğer peerlar non-core şablonuyla aynı:
```ini
[Interface]
Address = 10.10.0.5/24
ListenPort = 51820
MTU = 1420
PrivateKey = <node5_private_key>

# ... (gateway1/2, node1/2/3/4/7/8 aynı şekilde) ...

# node6 — sadece direkt IP
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node9 — backup + monitor + clickhouse (Faz 10'da eklenir; hot-add ile wg set kullanılabilir)
[Peer]
PublicKey = <node9_pubkey>
AllowedIPs = 10.10.0.13/32
Endpoint = <node9_public_ip>:51820
PersistentKeepalive = 25
```

**node6'nın kendi wg0.conf'u** — non-core şablonuyla aynı (node5 peer'ında VIP'ler var).

### 2.3 Başlatma

```bash
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0
```

### 2.4 Mesh Doğrulama

```bash
# Her node'dan tüm peer'lara ping at (Faz 2 mesh — node9 Faz 10'da eklenir):
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 \
          10.10.0.5 10.10.0.6 10.10.0.7 10.10.0.8 \
          10.10.0.9 10.10.0.12; do
  ping -c 1 -W 2 $ip && echo "OK $ip" || echo "FAIL $ip"
done
# NOT: 10.10.0.13 (node9) bu aşamada henüz kurulmamış olabilir — §10.0.3'te doğrulanır.

wg show wg0  # handshake zamanları güncel olmalı
```

### 2.5 Failover Sudoers — Tüm Non-Core Node'lar

Failover scriptinin SSH ile remote node'lara ulaşıp `sudo wg set` / `sudo wg-quick save wg0` çalıştırabilmesi için **tüm non-core node'larda** (gateway1, gateway2, node1, node2, node3, node4, node7, node8, node9) aşağıdaki sudoers kuralı eklenmeli:

```bash
# gateway1, gateway2, node1, node2, node3, node4, node7, node8, node9 — her birinde:
cat > /etc/sudoers.d/wg-vip << 'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *
tucibeyin ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick save wg0
EOF
chmod 440 /etc/sudoers.d/wg-vip
# Doğrula:
visudo -c -f /etc/sudoers.d/wg-vip
```

> **NOT:** Faz 4.5'te node6 için oluşturulan `/etc/sudoers.d/wg-vip` bu dosyanın aynısıdır — orada zaten bulunduğundan node6 için bu adım atlanır.

### 2.6 Guardian Sudoers — Servis Yönetimi (Tüm Node'lar)

`teqlif-guardian.service` `User=tucibeyin` olarak çalışır. Local Healer ve Command Executor, `systemctl restart/start/stop/reset-failed` çağırır. `tucibeyin` non-root olduğundan sudo yetkisi olmadan bu çağrılar `Permission Denied` verir — Local Healer hiçbir zaman çalışmaz.

**Tüm 11 node'da** (gateway1, gateway2, node1–node9) uygulama:

```bash
cat > /etc/sudoers.d/guardian-systemctl << 'EOF'
# guardian_agent.py Local Healer + Command Executor için
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start teqlif*
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop teqlif*
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart teqlif*
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload teqlif*
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed teqlif*
EOF
chmod 440 /etc/sudoers.d/guardian-systemctl
visudo -c -f /etc/sudoers.d/guardian-systemctl
```

**Per-node ek kurallar** — her rolün kendi Faz bölümünde eklenir:

| Node Rolü | Ek Servisler | Bölüm |
|-----------|-------------|-------|
| node5 / node6 (Core) | `pgbouncer`, `redis-core`, `redis-orch`, `redis-guardian` | §4.5 / §5.2 |
| node1 / node4 (Stream) | `livekit` | §7.2 / §12.2 |
| node7 / node8 (Storage) | `minio`, `nginx` | §6.4 / §6.6 |
| node9 (Monitor) | `prometheus`, `loki`, `alertmanager`, `grafana` | §10.1 |

> **guardian_agent.py implementasyon notu:** `systemctl()` helper mutlaka `subprocess(["sudo", "systemctl", action, unit], ...)` çağırmalı — `systemctl` direkt çağrısı `User=tucibeyin` altında `Interactive authentication required` hatası verir.

---

## Faz 3 — Rol Bazlı OS Tuning (Tüm Node'lar)

**Önkoşul:** Faz 2 tamamlandı.

### 3.1 Gateway (gateway1, gateway2)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.core.netdev_max_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW — 80/443 yalnızca Cloudflare IP aralıklarına açık (gerçek IP bypass'ını engeller):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat — tüm node'larda açık

# Cloudflare IPv4 aralıkları (kaynak: https://www.cloudflare.com/ips-v4/)
# Bu aralıklar değişebilir — https://www.cloudflare.com/ips/ adresinden periyodik kontrol et
for CF_IP in \
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
  141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
  197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 \
  104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
  ufw allow from ${CF_IP} to any port 80 proto tcp
  ufw allow from ${CF_IP} to any port 443 proto tcp
done

ufw --force enable

# Doğrulama — CF IP dışından doğrudan istek engellenmiş olmalı:
ufw status numbered | grep -E "80|443"
```

### 3.2 Core (node5, node6)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.swappiness = 1               # PostgreSQL buffer pool swap'a atılmasın; storage ile aynı kural
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
kernel.pid_max = 65536
net.core.somaxconn = 65535
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# node5/6 hiçbir servisi internete açmaz — tümü WireGuard üzerinden
ufw --force enable
```

### 3.3 Stream (node1, node4)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
# WebRTC UDP için büyük buffer
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.udp_rmem_min = 131072       # 128KB min per socket — LiveKit WebRTC
net.ipv4.udp_wmem_min = 131072
net.ipv4.udp_mem = 102400 873800 16777216
net.core.netdev_max_backlog = 65535
net.core.netdev_budget = 600         # tek NAPI poll'da daha fazla paket — yüksek PPS için
net.core.netdev_budget_usecs = 8000
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# LiveKit — internete açık portlar:
ufw allow 7880/tcp    # LiveKit API/WebRTC
ufw allow 7881/tcp    # LiveKit TCP fallback
ufw allow 7882/udp    # LiveKit UDP
ufw allow 3478/udp    # TURN UDP
ufw allow 5349/tcp    # TURN TLS
ufw allow 50000:60000/udp  # ICE UDP aralığı
ufw --force enable
```

### 3.4 Storage (node7, node8)

**Sysctl (node7 = node8 — özdeş):**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 50
vm.swappiness = 1              # NVMe olmasa da swap'tan kaç — 1 HDD üzerinde de doğru
fs.file-max = 200000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**HDD Optimizasyonu (her iki node):**
```bash
# udev rule — HDD için scheduler + readahead + derin I/O kuyruğu
cat > /etc/udev/rules.d/60-teqlif-hdd.rules << 'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", \
  ATTR{queue/scheduler}="mq-deadline", \
  ATTR{queue/read_ahead_kb}="2048", \
  ATTR{queue/nr_requests}="128"
EOF
udevadm control --reload-rules && udevadm trigger
```

**Swap Doğrulama (her iki node):**
```bash
# node7 + node8: 2.0 GB SSD swap beklenir
swapon --show
cat /etc/fstab | grep swap
# Kalıcı değilse /etc/fstab'a ekle
```

**UFW + iptables connection limit — node7/8 DNS Only olduğundan CF koruması yok; kernel seviyesinde savunma:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# uploads.teqlif.com DNS Only → doğrudan IP'ye gelir (CloudFlare koruması yok):
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# iptables hashlimit: tek IP'den 443'e max 60 yeni bağlantı/dakika (flood limiti)
# UFW zaten iptables kullandığından bu kural UFW kurallarından SONRA eklenmeli:
iptables -I INPUT -p tcp --dport 443 \
  -m hashlimit \
  --hashlimit-name https_flood \
  --hashlimit-above 60/min \
  --hashlimit-burst 80 \
  --hashlimit-mode srcip \
  -j DROP

iptables -I INPUT -p tcp --dport 80 \
  -m hashlimit \
  --hashlimit-name http_flood \
  --hashlimit-above 60/min \
  --hashlimit-burst 80 \
  --hashlimit-mode srcip \
  -j DROP

# Kalıcı hale getir:
apt-get install -y iptables-persistent
netfilter-persistent save
```

### 3.5 AI Proxy (node2) + Monitor (node9)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.swappiness = 5
fs.file-max = 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.overcommit_memory = 1   # node9: Prometheus + Loki mmap — overcommit olmadan ENOMEM alır
```

**UFW (node2 — AI Proxy):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
ufw --force enable
```

**UFW (node9 — Monitor + Backup + ClickHouse):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Grafana sadece WireGuard üzerinden erişilir:
# (ufw allow 3000/tcp AÇILMAZ — sadece wg0'dan erişilir)
ufw --force enable
```

**UFW (node3 — Staging):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Staging uygulama portları sadece WireGuard üzerinden:
# (ufw allow 8000/tcp AÇILMAZ — sadece wg0'dan erişilir)
ufw --force enable
```

### 3.6 Sysctl Uygulama

```bash
sysctl --system  # tüm /etc/sysctl.d/*.conf dosyalarını yükle
```

---

## Faz 4 — Veri Katmanı HA (node5 Primary + node6 Standby)

**Önkoşul:** Faz 3 tamamlandı.

### 4.1 PostgreSQL 17 — node5 Primary

**Kurulum (PGDG repo üzerinden):**
```bash
apt-get install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
apt-get install -y postgresql-17
```

**Memory planlama (node5: 7.8 GB RAM):**
- shared_buffers: 2 GB (RAM'in %25'i)
- Core Redis: 2 GB maxmemory
- Orch Redis: 256 MB maxmemory
- Guardian Redis: 128 MB maxmemory
- FastAPI (4 worker × ~150 MB): ~600 MB
- ARQ workers: ~300 MB
- ClickHouse: ~~500 MB~~ → **node9'a taşındı, 0 MB**
- OS: ~500 MB
- Toplam: ~5.8 GB → 2.0 GB boş + 8 GB swap güvenlik neti

**`/etc/postgresql/17/main/postgresql.conf`:**
```ini
# Bağlantı
listen_addresses = '*'   # Tüm interface — Keepalived VIP (10.10.0.10) failover'da otomatik bind; UFW WG dışını blokluyor
port = 5432
max_connections = 100

# Bellek (node5: 7.8 GB RAM, NVMe)
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 256MB
work_mem = 20MB
wal_buffers = 64MB

# NVMe için kritik ayarlar:
random_page_cost = 1.1
effective_io_concurrency = 200

# Checkpoint
checkpoint_completion_target = 0.9
min_wal_size = 1GB
max_wal_size = 4GB

# Replikasyon
wal_level = replica
max_wal_senders = 5
wal_keep_size = 2GB
max_slot_wal_keep_size = 5GB # node9 slot düşerse WAL birikmesini 5GB'la sınırlar; disk dolmaz
hot_standby = on
wal_log_hints = on           # pg_rewind için zorunlu (§5.6.1) — data checksums yoksa olmaz
max_replication_slots = 5    # pg_rewind + olası mantıksal replikasyon için

# Performans
default_statistics_target = 100
jit = off                    # PG17 OLTP: kısa tekrar sorgularda JIT compile overhead > execution time
```

**`/etc/postgresql/17/main/pg_hba.conf` — eklecek satırlar:**
```
# PgBouncer — lokal (node5 normal çalışma; node6 promote sonrası da lokal bağlanır)
host  teqlif  teqlif     127.0.0.1/32     scram-sha-256
# node9 — pg_dump (Faz 10.5 backup script)
host  teqlif  teqlif     10.10.0.13/32    scram-sha-256
# node6 streaming replication
host  replication  replicator  10.10.0.7/32  scram-sha-256
# node9 — pg_receivewal (sürekli WAL arşivleme) + pg_basebackup (haftalık fiziksel yedek)
host  replication  replicator  10.10.0.13/32 scram-sha-256
```

**Kullanıcı ve DB:**
```sql
CREATE USER teqlif WITH PASSWORD '<password>';
CREATE USER replicator WITH REPLICATION PASSWORD '<password>';
CREATE DATABASE teqlif OWNER teqlif;
```

### 4.2 PgBouncer — node5 ve node6

**Kurulum:**
```bash
apt-get install -y pgbouncer

# PgBouncer process crash sonrası otomatik kurtarma — paket varsayılanı restart içermez
mkdir -p /etc/systemd/system/pgbouncer.service.d
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/pgbouncer.service.d/restart.conf \
   /etc/systemd/system/pgbouncer.service.d/restart.conf
systemctl daemon-reload
```

**`/etc/pgbouncer/pgbouncer.ini`:**
```ini
[databases]
teqlif = host=127.0.0.1 port=5432 dbname=teqlif

[pgbouncer]
listen_addr = *              # 0.0.0.0 — Keepalived VIP 10.10.0.10 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_prepared_statements = 100  # asyncpg transaction mode'da statement_cache_size kapatmamak için GEREKLİ (PgBouncer 1.21+)
max_client_conn = 2000   # PgBouncer'ın asıl amacı: binlerce client'ı az PG bağlantısına sığdırmak
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
log_connections = 0
log_disconnections = 0
```

**`/etc/pgbouncer/userlist.txt`:**
```
"teqlif" "SCRAM-SHA-256$4096:<base64-salt>$<base64-storedKey>:<base64-serverKey>"
```

`auth_type = scram-sha-256` ile PgBouncer `md5` hash kabul etmez — SCRAM verifier veya plaintext şifre gerekir. SCRAM verifier üretmek için: `psql -c "SELECT rolpassword FROM pg_authid WHERE rolname='teqlif';"` çalıştır (node5'te `postgres` user ile); çıktıyı doğrudan userlist.txt'e yapıştır. Alternatif olarak plaintext kullanılabilir: `"teqlif" "<plaintext_password>"` — ama tercih edilmez.

Uygulama `DATABASE_URL` olarak `10.10.0.10:6432` (PG VIP üzerinden PgBouncer) kullanır.

### 4.3 Core Redis — node5 (port 6379)

```bash
apt-get install -y redis-server
# Varsayılan redis-server.service port 6379'da başlar — özel servislerle çakışır; devre dışı bırak:
systemctl disable --now redis-server
cp /etc/redis/redis.conf /etc/redis/redis-core.conf
mkdir -p /var/lib/redis-core
chown redis:redis /var/lib/redis-core
chmod 750 /var/lib/redis-core
```

**`/etc/redis/redis-core.conf` — değiştirilecek satırlar:**
```
port 6379
bind 0.0.0.0                 # Keepalived VIP 10.10.0.11 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
requirepass <core_redis_pass>
dir /var/lib/redis-core       # RDB + AOF dizini — backup script bu yolu kullanır
maxmemory 2gb
maxmemory-policy volatile-lru   # ARQ kuyruğu (TTL yok) silenmemeli; yalnızca TTL'li önbellek keyler silinir
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
save 900 1
save 300 10
save 60 10000
tcp-keepalive 300
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
loglevel notice
logfile /var/log/redis/redis-core.log
```

```bash
# redis-server.service'i KOPYALAMAK YASAK:
# Kopyalanan dosya PIDFile=/run/redis/redis-server.pid ve RuntimeDirectory=redis içerir.
# Üç Redis instance aynı PIDFile'ı paylaşırsa systemd PID takibini kaybeder.
# Çözüm: her instance için bağımsız service dosyası.
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/redis-core.service \
   /etc/systemd/system/redis-core.service
# node6'da: node6/systemd/redis-core.service (özdeş içerik)
systemctl daemon-reload
systemctl enable --now redis-core
```

### 4.4 Orch Redis — node5 (port 6380)

**`/etc/redis/redis-orch.conf`:**
```
port 6380
bind 0.0.0.0                 # Keepalived VIP 10.10.0.11 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
requirepass <orch_redis_pass>
dir /var/lib/redis-orch       # diğer instance'lardan izole çalışma dizini
maxmemory 256mb
maxmemory-policy noeviction
appendonly no
save ""               # ephemeral — disk'e yazma
hz 20                 # daha sık arka plan işi
activedefrag yes
active-defrag-threshold-lower 10
active-defrag-threshold-upper 30
loglevel notice
logfile /var/log/redis/redis-orch.log
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/redis-orch.service \
   /etc/systemd/system/redis-orch.service
# node6'da: node6/systemd/redis-orch.service (özdeş içerik)
systemctl daemon-reload
systemctl enable --now redis-orch
```

### 4.4.1 Guardian Redis — node5 (port 6382)

Guardian'ın özel veri kanalı. **Sadece `teqlif-guardian.service` okur ve yazar** — uygulama kodu, worker, başka hiçbir servis dokunmaz. Topology registry, job state machine, event stream, komut kanalları burada yaşar.

**`/etc/redis/redis-guardian.conf`:**
```
port 6382
bind 0.0.0.0
requirepass <guardian_redis_pass>       # .env.production'da GUARDIAN_REDIS_URL
dir /var/lib/redis-guardian             # appendonly AOF + RDB snapshot buraya yazılır; /var/lib/redis ile karışmasın
maxmemory 128mb
maxmemory-policy noeviction
appendonly yes                          # Guardian state kalıcı olmalı — job checkpoint'ler kaybolmamalı
appendfsync everysec
save 3600 1                             # 1h'de 1 değişiklik varsa snapshot
hz 20
activedefrag yes
loglevel notice
logfile /var/log/redis/redis-guardian.log
```

```bash
mkdir -p /var/lib/redis-orch /var/lib/redis-guardian
chown redis:redis /var/lib/redis-orch /var/lib/redis-guardian
chmod 750 /var/lib/redis-orch /var/lib/redis-guardian

cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/redis-guardian.service \
   /etc/systemd/system/redis-guardian.service
# node6'da: node6/systemd/redis-guardian.service (özdeş içerik)
systemctl daemon-reload
systemctl enable --now redis-guardian
redis-cli -p 6382 -a <guardian_redis_pass> ping  # → PONG
```

> **node6'da da kurulur** (§4.7 redis replikasyon bölümünde) — Keepalived failover'da `REPLICAOF NO ONE` ile standalone'a geçer, tıpkı redis-orch gibi.

> **UFW:** guardian-redis portu (6382) sadece WireGuard mesh içinden erişilebilir — node5/node6 dışındaki node'larda guardian agent bağlanır. Dış dünyaya kapalı.

> **Heartbeat portu:** UDP 9901 tüm node'larda `ufw allow in on wg0 proto udp to any port 9901` ile açılır (§1.5 UFW kurallarına eklenir).

### 4.5 Keepalived — node5 (MASTER)

```bash
apt-get install -y keepalived
```

**`/etc/keepalived/keepalived.conf` — node5:**
```
vrrp_script chk_postgres {
    # pg_isready: postgresql-client paketiyle gelir — nagios-plugins bağımlılığı yok
    script "/usr/bin/pg_isready -h 127.0.0.1 -p 5432 -q"
    interval 2
    weight -20
}

vrrp_script chk_redis {
    script "/usr/bin/redis-cli -p 6379 -a <core_redis_pass> --no-auth-warning ping"
    interval 2
    weight -20
}

# VRRP sync group: VI_PG ve VI_Redis her zaman birlikte failover yapar.
# Biri düşse bile ikisi de geçer — split VIP routing'i engeller.
vrrp_sync_group VG_CORE {
    group {
        VI_PG
        VI_Redis
    }
    notify_master "/etc/keepalived/scripts/wg_vip_node5.sh MASTER"
    notify_backup "/etc/keepalived/scripts/wg_vip_node5.sh BACKUP"
}

# ⚠️ WireGuard üzerinde VRRP multicast çalışmaz.
# VRRP advertisement'ları 224.0.0.18'e gönderilir; WireGuard AllowedIPs'de
# multicast tanımlı değil → paketler iletilmez → her iki node MASTER olur (split-brain).
# Çözüm: unicast_src_ip + unicast_peer ZORUNLUdur.

vrrp_instance VI_PG {
    state MASTER
    interface wg0
    virtual_router_id 51
    priority 110
    nopreempt              # failback manüeldir: node5 boot edince otomatik preempt etmez
    advert_int 1
    unicast_src_ip 10.10.0.5        # node5 wg0 IP
    unicast_peer {
        10.10.0.7                   # node6 wg0 IP
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.10/32
    }
    track_script { chk_postgres chk_redis }
}

vrrp_instance VI_Redis {
    state MASTER
    interface wg0
    virtual_router_id 52
    priority 110
    nopreempt              # failback manüeldir: node5 boot edince otomatik preempt etmez
    advert_int 1
    unicast_src_ip 10.10.0.5
    unicast_peer {
        10.10.0.7
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.11/32
    }
    track_script { chk_postgres chk_redis }
}
```

> **`nopreempt` zorunludur:** Olmasa, node5 crash→boot sonrası keepalived otomatik priority 110'la preempt yapar. WG routing node6'nın notify_backup'ı tarafından güncellenir ama node5'te PgBouncer disabled, PostgreSQL diverged timeline'da → uygulama çalışmaz, split-brain riski. `nopreempt` ile failback tamamen manüel kontrol altında kalır.

**`/etc/keepalived/scripts/wg_vip_node5.sh` — node5'te:**
```bash
# node5'te kurulur; failback (node6→node5 VIP dönüşü) sırasında tetiklenir.
# MASTER bloğu WG routing güncellemez — node6'nın notify_backup'ı failback'te routing'i zaten günceller.
mkdir -p /etc/keepalived/scripts
cat > /etc/keepalived/scripts/wg_vip_node5.sh << 'SCRIPT'
#!/bin/bash
STATE="${1}"
SECRETS_FILE="/etc/keepalived/secrets/failover.env"
[ -f "${SECRETS_FILE}" ] && source "${SECRETS_FILE}"

if [ "$STATE" = "MASTER" ]; then
    # PostgreSQL failback sonrası recovery'deyse promote et
    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2
    fi

    # PgBouncer: standby'da disabled edilmişti
    systemctl enable pgbouncer
    systemctl start pgbouncer

    # Uygulama servislerini başlat (teqlif-guardian tüm node'larda her zaman aktif — başlatma)
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian

    # Telegram bildirimi
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILBACK TAMAMLANDI: node6→node5 VIP geri dönüşü* — servisler aktif" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true

else
    # node5 BACKUP: health check düşünce node6 MASTER oluyor
    # teqlif-guardian durdurulmuyor — agent tüm node'larda çalışır; sadece app servisleri durur
    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
    systemctl disable pgbouncer
fi

logger "wg_vip_node5: STATE=${STATE} completed"
SCRIPT
chmod 750 /etc/keepalived/scripts/wg_vip_node5.sh

# Secrets (node5'te):
mkdir -p /etc/keepalived/secrets
chmod 700 /etc/keepalived/secrets          # dizin de kilitli; 755 kalırsa dosya adı görünür
chown root:root /etc/keepalived/secrets
cat > /etc/keepalived/secrets/failover.env << 'EOF'
TELEGRAM_BOT_TOKEN="<telegram_bot_token>"
TELEGRAM_CHAT_ID_ALERTS="<telegram_chat_id_alerts>"
EOF
chmod 600 /etc/keepalived/secrets/failover.env
chown root:root /etc/keepalived/secrets/failover.env

systemctl enable --now keepalived
```

**`/etc/keepalived/keepalived.conf` — node6:** `state BACKUP`, `priority 100`; unicast_src_ip/peer ters; vrrp_script tanımları ve sync group notify callback'leri var:

```
vrrp_script chk_postgres {
    script "/usr/bin/pg_isready -h 127.0.0.1 -p 5432 -q"
    interval 2
    weight -20
}

vrrp_script chk_redis {
    script "/usr/bin/redis-cli -p 6379 -a <core_redis_pass> --no-auth-warning ping"
    interval 2
    weight -20
}

vrrp_sync_group VG_CORE {
    group {
        VI_PG
        VI_Redis
    }
    notify_master "/etc/keepalived/scripts/wg_vip_failover.sh MASTER"
    notify_backup "/etc/keepalived/scripts/wg_vip_failover.sh BACKUP"
}

vrrp_instance VI_PG {
    state BACKUP
    interface wg0
    virtual_router_id 51
    priority 100
    advert_int 1
    unicast_src_ip 10.10.0.7        # node6 wg0 IP
    unicast_peer {
        10.10.0.5                   # node5 wg0 IP
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.10/32
    }
    track_script { chk_postgres chk_redis }
}

vrrp_instance VI_Redis {
    state BACKUP
    interface wg0
    virtual_router_id 52
    priority 100
    advert_int 1
    unicast_src_ip 10.10.0.7
    unicast_peer {
        10.10.0.5
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.11/32
    }
    track_script { chk_postgres chk_redis }
}
```

**`/etc/keepalived/scripts/wg_vip_failover.sh` — node6'da:**

```bash
#!/bin/bash
# Keepalived sync group notify: WireGuard VIP AllowedIPs güncelleme + Redis config temizleme.
# node6 MASTER olunca: tüm non-core node'larda VIP'ler node5→node6'ya taşınır.
# node6 BACKUP olunca: ters işlem.

STATE=$1   # MASTER veya BACKUP

# Şifreler script içinde hardcoded değil — ayrı dosyadan okunur (600 root:root)
SECRETS_FILE="/etc/keepalived/secrets/failover.env"
if [ ! -f "${SECRETS_FILE}" ]; then
    logger "wg_vip_failover: HATA — secrets dosyası bulunamadı: ${SECRETS_FILE}"
    exit 1
fi
. "${SECRETS_FILE}"
# secrets dosyası içeriği (örnek — gerçek değerler VPS'te doldurulur):
# ORCH_REDIS_PASS="<orch_redis_pass>"
# NODE5_PUBKEY="<node5_pubkey>"
# NODE6_PUBKEY="<node6_pubkey>"

if [ "$STATE" = "MASTER" ]; then
    # Split-brain guard: node5 WireGuard üzerinden hâlâ erişilebiliyorsa bu muhtemelen
    # yanlış bir MASTER geçişidir (WG link problemi, node5 yaşıyor). Abort et.
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
           -i /home/tucibeyin/.ssh/id_ed25519_failover \
           tucibeyin@10.10.0.5 "exit 0" 2>/dev/null; then
        logger "wg_vip_failover: MASTER geçişi iptal — node5 (10.10.0.5) hâlâ erişilebilir (split-brain riski). Manuel müdahale gerekiyor."
        exit 1
    fi

    NEW_PRIMARY_PUBKEY="${NODE6_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.7/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE5_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.5/32"
else
    NEW_PRIMARY_PUBKEY="${NODE5_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.5/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE6_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.7/32"
fi

# 1. Tüm non-core node'larda live WG routing güncelle (paralel — senkron SSH 5s×N gecikme yaratır)
ALL_WG_IPS="10.10.0.2 10.10.0.9 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.8 10.10.0.12 10.10.0.13"

for WG_IP in ${ALL_WG_IPS}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i /home/tucibeyin/.ssh/id_ed25519_failover \
        tucibeyin@${WG_IP} \
        "sudo wg set wg0 peer ${NEW_PRIMARY_PUBKEY} allowed-ips ${NEW_PRIMARY_IPS} && \
         sudo wg set wg0 peer ${NEW_STANDBY_PUBKEY} allowed-ips ${NEW_STANDBY_IPS}" \
        2>/dev/null || true &  # paralel: down node 5s beklemez, diğerleri engellenmez
done
wait  # tüm arka plan SSH'ların bitmesini bekle

# 2. Yerel (node6) WG routing güncelle
sudo wg set wg0 peer "${NEW_PRIMARY_PUBKEY}" allowed-ips "${NEW_PRIMARY_IPS}"
sudo wg set wg0 peer "${NEW_STANDBY_PUBKEY}" allowed-ips "${NEW_STANDBY_IPS}"

# 3. MASTER olduğumuzda: Redis config'den replicaof kaldır (restart sonrası kendine bağlanmasın)
#    BACKUP olduğumuzda: yeniden ekle (node5 primary'ya replica ol)
if [ "$STATE" = "MASTER" ]; then
    # 3a. Core Redis'i canlı olarak standalone yap — config değişikliği tek başına yetmez,
    #     process replica modunda kalmaya devam eder (read-only → yazma başarısız)
    redis-cli -p 6379 -a "${CORE_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-core.conf   # restart sonrası da standalone kalır

    # 3b. Orch Redis'i canlı olarak standalone yap — DEL ve orchestrator SET NX bundan sonra çalışır
    redis-cli -p 6380 -a "${ORCH_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-orch.conf

    # 3c. Guardian Redis'i canlı olarak standalone yap — job checkpoint'leri ve lider seçimi buradan beslenir
    #     Sadece config değiştirmek yetmez: process replica modunda (read-only) kalmaya devam eder
    redis-cli -p 6382 -a "${GUARDIAN_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-guardian.conf

    # 4. PostgreSQL promote — standby → primary (zaten primary ise atla)
    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2  # promote'un tamamlanmasını bekle
    fi

    # 4a. WAL backup replication slotu oluştur — node9 pg_receivewal için
    # (slot node5'te oluşturulmuştu; pg_basebackup slot state'i kopyalamaz → node6'da yoktur)
    sudo -u postgres psql -c \
      "SELECT pg_create_physical_replication_slot('wal_backup_node9') \
       WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='wal_backup_node9');" \
      2>/dev/null || true

    # 5. PgBouncer başlat ve enable et (standby'da disabled'dı — reboot kalıcılığı için enable şart)
    systemctl enable pgbouncer
    systemctl start pgbouncer

    # 6. Uygulama servislerini başlat (teqlif-guardian agent her zaman çalışır — sadece app servisleri başlar)
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian

    # 7. Uzak node'larda WireGuard config'i diske yaz (reboot sonrası da kalıcı olsun — paralel)
    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} \
            "sudo wg-quick save wg0" \
            2>/dev/null || true &
    done
    wait
    # Yerel node6'da da diske yaz:
    wg-quick save wg0

    # 8. Telegram #alerts bildirimi (hata olsa da devam et)
    source "${SECRETS_FILE}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILOVER TAMAMLANDI: node5→node6 VIP geçişi* — PG promote + servisler aktif" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true

else
    # 1. WireGuard VIP routing güncelle: VIP'ler node5'e geri dön (paralel)
    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} \
            "sudo wg set wg0 peer ${NEW_PRIMARY_PUBKEY} allowed-ips ${NEW_PRIMARY_IPS} && \
             sudo wg set wg0 peer ${NEW_STANDBY_PUBKEY} allowed-ips ${NEW_STANDBY_IPS}" \
            2>/dev/null || true &
    done
    wait

    # 2. Yerel (node6) WG routing güncelle
    sudo wg set wg0 peer "${NEW_PRIMARY_PUBKEY}" allowed-ips "${NEW_PRIMARY_IPS}"
    sudo wg set wg0 peer "${NEW_STANDBY_PUBKEY}" allowed-ips "${NEW_STANDBY_IPS}"

    # 3. Failback: node5 VIP'i tekrar aldığında node6 replica olmalı
    # Servisleri durdur ve pgbouncer'ı disable et — reboot'ta standby'da yeniden başlamasın
    # teqlif-guardian durdurulmuyor — agent her node'da her zaman çalışır
    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
    systemctl disable pgbouncer

    grep -q '^replicaof' /etc/redis/redis-core.conf || \
        echo "replicaof 10.10.0.11 6379" >> /etc/redis/redis-core.conf
    grep -q '^replicaof' /etc/redis/redis-orch.conf || \
        echo "replicaof 10.10.0.11 6380" >> /etc/redis/redis-orch.conf
    grep -q '^replicaof' /etc/redis/redis-guardian.conf || \
        echo "replicaof 10.10.0.5 6382" >> /etc/redis/redis-guardian.conf
    # NOT: guardian-redis VIP üzerinden replika olmaz (guardian-redis VIP'te değil, direkt IP'de)
    # Failback: node5 geri döndüğünde guardian-redis node5:6382'ye bağlanır
    # Redis'i yeniden başlat ki yeni primary'ya (node5 VIP/IP) bağlansın
    systemctl restart redis-core redis-orch redis-guardian

    # 4. Uzak node'larda WireGuard config'i diske yaz (paralel)
    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} \
            "sudo wg-quick save wg0" \
            2>/dev/null || true &
    done
    wait
    wg-quick save wg0
fi

logger "wg_vip_failover: STATE=${STATE} completed"
```

**SSH keypair — node6'da failover için ayrı anahtar üret:**
```bash
# node6'da:
su - tucibeyin -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_failover -N ''"
# Üretilen public key'i (~/.ssh/id_ed25519_failover.pub) diğer tüm node'ların
# /home/tucibeyin/.ssh/authorized_keys dosyasına ekle:
# Hedef node'lar: gateway1 (10.10.0.2), gateway2 (10.10.0.9), node1 (10.10.0.1),
#   node2 (10.10.0.3), node3 (10.10.0.4), node4 (10.10.0.6),
#   node7 (10.10.0.8), node8 (10.10.0.12), node9 (10.10.0.13)
# NOT: node9 Faz 10'da kurulur — o fazda authorized_keys ekleme adımı hatırlatılır (§10.6.1).
cat /home/tucibeyin/.ssh/id_ed25519_failover.pub
# → Bu çıktıyı her node'da: echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
```

```bash
# Secrets dizini + failover.env (600 root:root — script içinde hardcoded değil):
mkdir -p /etc/keepalived/secrets
chmod 700 /etc/keepalived/secrets          # dizin de kilitli; 755 kalırsa dosya adı görünür
chown root:root /etc/keepalived/secrets
cat > /etc/keepalived/secrets/failover.env << 'EOF'
CORE_REDIS_PASS="<core_redis_pass>"
ORCH_REDIS_PASS="<orch_redis_pass>"
GUARDIAN_REDIS_PASS="<guardian_redis_pass>"
NODE5_PUBKEY="<node5_pubkey>"
NODE6_PUBKEY="<node6_pubkey>"
TELEGRAM_BOT_TOKEN="<telegram_bot_token>"
TELEGRAM_CHAT_ID_ALERTS="<telegram_chat_id_alerts>"
EOF
chmod 600 /etc/keepalived/secrets/failover.env
chown root:root /etc/keepalived/secrets/failover.env

mkdir -p /etc/keepalived/scripts
chmod 750 /etc/keepalived/scripts/wg_vip_failover.sh
# sudoers: wg set (routing) + wg-quick save (diske yazma) — §2.5 ile aynı kural
cat > /etc/sudoers.d/wg-vip << 'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *
tucibeyin ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick save wg0
EOF
chmod 440 /etc/sudoers.d/wg-vip
visudo -c -f /etc/sudoers.d/wg-vip

systemctl enable --now keepalived
```

### 4.6 PostgreSQL Streaming Replication — node6

```bash
# node6'da:
systemctl stop postgresql
su - postgres -c "pg_basebackup \
  -h 10.10.0.5 -U replicator \
  -D /var/lib/postgresql/17/main \
  -Xs -P -R"
# -R: standby.signal + primary_conninfo otomatik oluşturur

# pg_basebackup node5'in postgresql.conf'unu kopyalar.
# listen_addresses = '*' — node5'ten kopyalandı; node6 için de geçerli. Değiştirme gerekmez.
grep listen_addresses /var/lib/postgresql/17/main/postgresql.conf  # → * olmalı

# node6 disk override — node5 NVMe ayarları (random_page_cost=1.1, effective_io_concurrency=200)
# pg_basebackup ile kopyalanır ama node6 diski ~5× daha yavaş (2.5K vs 11.6K IOPS).
# Planner bu ayarlarla "disk çok hızlı" sanıp index scan seçer → failover sonrası DB kilitlenir.
cat >> /var/lib/postgresql/17/main/postgresql.conf << 'EOF'

# --- node6 disk override (pg_basebackup sonrası — node5 NVMe ayarlarını ezip geçer) ---
random_page_cost = 4.0          # node5: 1.1 (NVMe) → node6 Deluxhost ~2.5K IOPS; varsayılan 4.0 doğru
effective_io_concurrency = 8    # node5: 200 (NVMe paralel I/O) → node6 için uygun değer
EOF

systemctl start postgresql
```

> **ÖNEMLİ — node9 eklendiğinde (Faz 10):** pg_basebackup veri dizinini kopyalar; `pg_hba.conf` da bu kopyanın içindedir. Ancak Faz 10'da node9 eklendikten sonra node5'e eklenen pg_hba.conf girişleri **WAL streaming replication ile node6'ya otomatik yansımaz** — config dosyası değişiklikleri WAL kapsamı dışındadır. node9 backup bağlantıları başarısız olmasın diye §10.6.1'de node6 pg_hba.conf'u da güncellenir.

**Doğrulama:**
```bash
# node6'da:
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"
# → t

# node5'te:
psql -h 127.0.0.1 -U postgres -c "SELECT * FROM pg_stat_replication;"
# → node6'yı görmeli
```

### 4.7 Redis Replication — node6

```bash
# VIP üzerinden replication (10.10.0.11) — node5→node6 geçişinde replication hedefi değişmez
cat >> /etc/redis/redis-core.conf << 'EOF'
replicaof 10.10.0.11 6379
masterauth <core_redis_pass>
EOF

cat >> /etc/redis/redis-orch.conf << 'EOF'
replicaof 10.10.0.11 6380
masterauth <orch_redis_pass>
EOF

# Guardian Redis — node5 direkt IP üzerinden replika (VIP'te değil)
# Guardian-redis VIP'e bağlanmaz çünkü guardian-redis Keepalived VIP kapsamı dışında
cat >> /etc/redis/redis-guardian.conf << 'EOF'
replicaof 10.10.0.5 6382
masterauth <guardian_redis_pass>
EOF

systemctl restart redis-core redis-orch redis-guardian

# Doğrula:
redis-cli -h 127.0.0.1 -p 6379 -a <core_redis_pass> info replication | grep role  # → role:slave
redis-cli -h 127.0.0.1 -p 6380 -a <orch_redis_pass> info replication | grep role  # → role:slave
redis-cli -h 127.0.0.1 -p 6382 -a <guardian_redis_pass> info replication | grep role  # → role:slave
```

### 4.9 Faz 4 Doğrulama

```bash
# node5
psql -h 127.0.0.1 -p 5432 -U teqlif -d teqlif -c "SELECT version();"
psql -h 127.0.0.1 -p 6432 -U teqlif -d teqlif -c "SELECT 1;"  # PgBouncer
redis-cli -p 6379 -a <pass> ping   # → PONG
redis-cli -p 6380 -a <pass> ping   # → PONG
clickhouse-client --query "SELECT 1"

# VIP üzerinden erişim
psql -h 10.10.0.10 -p 6432 -U teqlif -d teqlif -c "SELECT 1;"
redis-cli -h 10.10.0.11 -p 6379 -a <pass> ping
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ping
```

---

## Faz 5 — Core App (node5 Primary + node6 Standby)

**Önkoşul:** Faz 4 tamamlandı.

### 5.1 Repo ve Python Ortamı — node5

```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r backend/requirements.txt
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

### 5.1.1 Alembic — DB Şema Kurulumu (repo klonlandıktan sonra)

```bash
cd /var/www/teqlif.com/backend
source ../.venv/bin/activate
# ⚠️ PgBouncer (6432) transaction pooling modunda LOCK TABLE desteklemez.
# alembic için doğrudan PostgreSQL portunu (5432) kullan:
DATABASE_URL="postgresql+asyncpg://teqlif:<pass>@10.10.0.10:5432/teqlif" alembic upgrade head
python3 scripts/sync_translations.py
python3 scripts/sync_category_fields.py
```

### 5.2 .env.production — node5

Template'den oluştur, gerçek değerleri doldur:

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur: şifre, API key, token vb.
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

### 5.3 Systemd Servisleri — node5

**`/etc/systemd/system/teqlif.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/teqlif.service \
   /etc/systemd/system/teqlif.service
```

**`/etc/systemd/system/teqlif-worker.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/teqlif-worker.service \
   /etc/systemd/system/teqlif-worker.service
```

**`/etc/systemd/system/teqlif-worker-critical.service`** (CriticalWorkerSettings, MemoryMax=800M):
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/teqlif-worker-critical.service \
   /etc/systemd/system/teqlif-worker-critical.service
```

**`/etc/systemd/system/teqlif-guardian.service`** (tüm node'larda aynı unit — paylaşımlı kaynak):
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif teqlif-worker teqlif-worker-critical teqlif-guardian
```

### 5.3.1 teqlif-ai-proxy — node5 (Son Çare Fallback)

node5 AI proxy'yi **aktif olarak çalıştırmaz**; `teqlif-ai-proxy.service` kurulu ve disabled olarak bekler. Orchestrator node2 + node3 ikisi de down olduğunda bu servisi locally başlatır ve `ai_proxy:active_url=http://10.10.0.5:8001` yazar.

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/teqlif-ai-proxy.service \
   /etc/systemd/system/teqlif-ai-proxy.service
```

```bash
systemctl daemon-reload
# Disabled: sadece orchestrator başlatır; manuel ya da boot'ta aktif olmaz
# systemctl enable teqlif-ai-proxy  ← YAPMA; orchestrator yönetir
```

### 5.4 Ops Komutları Kurulumu

```bash
cp /var/www/teqlif.com/scripts/teqlif-restart.sh /usr/local/sbin/teqlif-restart
cp /var/www/teqlif.com/scripts/teqlif-refresh.sh  /usr/local/sbin/teqlif-refresh
chmod 750 /usr/local/sbin/teqlif-restart /usr/local/sbin/teqlif-refresh
```

### 5.5 node6 — Standby App Kurulumu

```bash
# node6'da — node5 ile aynı monorepo + .env (VIP'ler aynı)
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt

cp /var/www/teqlif.com/deploy/scale/V2.0/node6/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**node6 systemd servisleri** (node5'ten farklı: `--workers 3`, guardian paylaşımlı):
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node6/systemd/teqlif.service \
   /etc/systemd/system/teqlif.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node6/systemd/teqlif-worker.service \
   /etc/systemd/system/teqlif-worker.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node6/systemd/teqlif-worker-critical.service \
   /etc/systemd/system/teqlif-worker-critical.service
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
```

**node6'da teqlif/worker/orchestrator servisleri:** Kurulu ama **disabled + stopped** — Keepalived VIP geçişinde `notify_master` scriptiyle aktif olur.

```bash
systemctl disable teqlif teqlif-worker teqlif-worker-critical
# teqlif-guardian tüm node'larda her zaman aktif — standby'da da çalışır (agent görevini yapar)
# keepalived aktif kalır; pgbouncer standby'da disabled — VIP geçişinde notify_master başlatır:
systemctl enable --now teqlif-guardian keepalived redis-core redis-orch redis-guardian
systemctl disable pgbouncer   # standby'da PgBouncer çalışmaz; failover sonrası notify_master tetikler
```

### 5.6 Failover Testi

`wg_vip_failover.sh MASTER` (node6'daki callback) PG promote, Redis promote, PgBouncer start ve teqlif servis başlatmayı otomatik yapar. Test yalnızca tetikleyici + doğrulama adımlarından oluşur.

```bash
# 1. node5'te keepalived durdur (simülasyon — notify_master node6'da tetiklenir, ~15-30s):
sudo systemctl stop keepalived

# 2. node6'da — otomatik çalışan adımları doğrula:

# VIP geçişi (~3s):
ip addr show wg0 | grep "10.10.0.10\|10.10.0.11"
# → her iki VIP node6'nın wg0'ında görünmeli

# WireGuard routing (notify_master step 1):
wg show wg0 | grep -A2 "peer"
# node5 peer → allowed-ips: 10.10.0.5/32  (VIP'ler kalkmış)
# Herhangi bir edge node'da (örn. gateway1):
ssh 10.10.0.2 "wg show wg0 | grep -A2 peer"
# node6 peer'ında 10.10.0.10/32 ve 10.10.0.11/32 görünmeli

# PostgreSQL promote (notify_master step 4):
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"
# → f (primary)

# Redis primary (notify_master step 3):
redis-cli -h 127.0.0.1 -p 6379 -a <pass> info replication | grep role
# → role:master

# PgBouncer + uygulama (notify_master step 5-6):
systemctl is-active pgbouncer teqlif teqlif-worker teqlif-worker-critical teqlif-guardian
# → hepsi active

# Health check:
curl -s http://127.0.0.1:8000/health | jq .  # → {"status":"ok"}
```

- [ ] Başarılı → failback prosedürü §5.6.1 adımlarıyla test et

### 5.6.1 Failback Prosedürü (node5 geri gelince)

node5 restore edildiğinde doğrudan primary olamaz — veri uyuşmazlığı vardır. `nopreempt` ile failback tamamen manüel kontrol altındadır; keepalived otomatik preempt etmez.

**ADIM 1 — node5'te keepalived durdur/disable et (sync öncesi zorunlu):**
```bash
# node5'te — ÖNCE yapılmalı: aksi hâlde PostgreSQL sync tamamlanmadan MASTER olur
systemctl stop keepalived
systemctl disable keepalived   # reboot'ta otomatik başlamasın; failback sonunda re-enable et
```

**ADIM 2 — node5'i PostgreSQL replica olarak node6'ya bağla:**
```bash
# node5'te:
systemctl stop postgresql

# pg_rewind dener (daha hızlı — ortak timeline checkpoint varsa):
su - postgres -c "pg_rewind \
  --target-pgdata=/var/lib/postgresql/17/main \
  --source-server='host=10.10.0.7 user=replicator password=<pass>'"

# pg_rewind başarısız olursa (örn. WAL uçtu): pg_basebackup ile taze başla
# su - postgres -c "rm -rf /var/lib/postgresql/17/main && \
#   pg_basebackup -h 10.10.0.7 -U replicator \
#   -D /var/lib/postgresql/17/main -Xs -P -R"

# standby.signal ve primary_conninfo kontrol — node6 IP'sini göstermeli:
cat /var/lib/postgresql/17/main/standby.signal
cat /var/lib/postgresql/17/main/postgresql.auto.conf
# primary_conninfo = 'host=10.10.0.7 ...'

systemctl start postgresql
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"  # → t
```

**ADIM 3 — Replay lag sıfırlanana kadar bekle:**
```bash
# node6'da:
psql -h 127.0.0.1 -U postgres -c \
  "SELECT write_lag, flush_lag, replay_lag \
   FROM pg_stat_replication WHERE application_name='walreceiver';"
# → tüm lag sütunları NULL veya ~0
```

**ADIM 4 — node6'da servisleri durdur ve keepalived'ı kapat:**
```bash
# node6'da:
systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
# teqlif-guardian durdurulmuyor — agent her node'da her zaman çalışır
# keepalived durdur → notify_backup tetiklenir:
#   WG routing VIP'leri node5'e yönlendirir, Redis replicaof eklenir
# node5 artık tek VRRP instance → otomatik MASTER olur → wg_vip_node5.sh MASTER tetiklenir
systemctl stop keepalived
```

**ADIM 5 — node5 keepalived başlat (MASTER olur):**
```bash
# node5'te:
systemctl enable keepalived
systemctl start keepalived
# wg_vip_node5.sh MASTER otomatik çalışır:
#   PostgreSQL promote (recovery'deyse) + PgBouncer enable+start + teqlif servisler start

# Doğrula:
ip addr show wg0 | grep "10.10.0.10\|10.10.0.11"               # VIP'ler node5'te
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();" # → f (primary)
curl -s http://127.0.0.1:8000/health | jq .                     # → {"status":"ok"}
```

**ADIM 6 — node6'yı BACKUP olarak hazırla:**
```bash
# node6'da — node5'in replikasyon bağlantısına izin ver:
echo "host replication replicator 10.10.0.5/32 scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
systemctl reload postgresql
# node6 keepalived'ı yeniden etkinleştir (BACKUP modunda bekler):
systemctl enable --now keepalived
```

### 5.6.2 Failover Sırasında Ulaşılamayan Node'ların WG Routing Düzeltmesi

`wg_vip_failover.sh` SSH loop'u `|| true` ile çalışır — geçici olarak down olan node atlanır. Uygulama servis kesmeden korunur; ancak node ayağa kalktığında WG routing'i eski primary'yı göstermeye devam eder.

**Kontrol (failover sonrası, node6 MASTER olduğunda):**
```bash
# node6'dan — tüm non-core node'larda VIP routing'i doğrula:
# Beklenen: NODE6_PUBKEY'in allowed-ips'inde 10.10.0.10 VE 10.10.0.11 var olmalı
NODE6_PUBKEY=$(wg show wg0 | awk '/public key/{print $3; exit}')
for WG_IP in 10.10.0.2 10.10.0.9 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.8 10.10.0.12 10.10.0.13; do
  printf "=== %s === " "${WG_IP}"
  ssh -o ConnectTimeout=5 -o BatchMode=yes \
      -i /home/tucibeyin/.ssh/id_ed25519_failover \
      tucibeyin@${WG_IP} \
      "wg show wg0 | grep -A3 '${NODE6_PUBKEY}' | grep allowed-ips" 2>/dev/null \
    || echo "ULAŞILAMADI veya routing eksik"
done
# Sağlıklı satır: allowed-ips: 10.10.0.7/32, 10.10.0.10/32, 10.10.0.11/32
```

**Stale veya ulaşılamayan node varsa manuel düzelt:**
```bash
# Eksik node'a SSH at (WG zaten bağlıysa WG IP'siyle, değilse public IP'siyle):
STALE_NODE_IP="<node_wg_ip>"

# failover.env'deki pubkey'leri node6'dan oku:
source /etc/keepalived/secrets/failover.env
NODE5_PUBKEY="${NODE5_PUBKEY}"   # node5 = artık standby
NODE6_PUBKEY="${NODE6_PUBKEY}"   # node6 = artık primary (VIP sahibi)

ssh -i /home/tucibeyin/.ssh/id_ed25519_failover tucibeyin@${STALE_NODE_IP} "
  sudo wg set wg0 peer ${NODE6_PUBKEY} allowed-ips 10.10.0.7/32,10.10.0.10/32,10.10.0.11/32 &&
  sudo wg set wg0 peer ${NODE5_PUBKEY} allowed-ips 10.10.0.5/32 &&
  sudo wg-quick save wg0
"
# Doğrula:
ssh tucibeyin@${STALE_NODE_IP} "wg show wg0 | grep -A3 '${NODE6_PUBKEY}'"
```

### 5.7 Faz 5 Doğrulama

```bash
# node5
systemctl status teqlif teqlif-worker teqlif-worker-critical teqlif-guardian
curl -s http://127.0.0.1:8000/health | jq .
```

---

## Faz 6 — Storage (node7 + node8)

**Önkoşul:** Faz 5 tamamlandı. (Guardian ve LiveKit için Veri Katmanı / Redis VIP hazır olmalıdır.)

### 6.1 HDD Formatı ve Mount — Her İki Node

```bash
# Mevcut disk yapısını kontrol et:
lsblk
# HDD'yi belirle (genellikle /dev/sdb veya /dev/vdb)

# Format:
mkfs.xfs -L teqlif-data /dev/sdb

# Mount noktası:
mkdir -p /mnt/data

# /etc/fstab'a ekle (largeio+allocsize: büyük obje yazma throughput; inode64: 1TB+ fs üzerinde inode dağıtımı):
echo "LABEL=teqlif-data /mnt/data xfs defaults,noatime,largeio,inode64,allocsize=64m 0 2" >> /etc/fstab
mount -a

# MinIO dizini:
mkdir -p /mnt/data/minio
chown tucibeyin:tucibeyin /mnt/data/minio
chmod 700 /mnt/data/minio
```

**`noatime`:** HDD'de her okumada inode güncellenmesini engeller — performans için kritik.

### 6.2 MinIO Kurulumu

```bash
# MinIO binary indir (GitHub releases — dl.min.io kullanma, 410 döner):
# Pinned release — latest yerine belirli bir sürüm kullan (asset adı: minio.linux-amd64.RELEASE.YYYY-...Z):
MINIO_RELEASE="RELEASE.2024-11-07T00-52-20Z"   # kurulum sırasında https://github.com/minio/minio/releases adresinden son kararlı sürümü kontrol et
curl -fsSL "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/minio.linux-amd64.${MINIO_RELEASE}" \
  -o /usr/local/bin/minio
chmod +x /usr/local/bin/minio
/usr/local/bin/minio --version   # doğrula
```

### 6.3 node7 — MinIO Servisi

```bash
# Template'den oluştur — içerik Faz 0.5'te tanımlı (ORCH_REDIS_URL, EDGE_NODE_ID, MINIO_VOLUMES vb.):
cp /var/www/teqlif.com/deploy/scale/V2.0/node7/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur: MINIO_ROOT_USER, MINIO_ROOT_PASSWORD vb.
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/systemd/system/minio.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node7/systemd/minio.service \
   /etc/systemd/system/minio.service
# node8'de: node8/systemd/minio.service (özdeş içerik)
```

```bash
mkdir -p /var/log/teqlif/minio
systemctl enable --now minio
```

**Bucket oluşturma (node7 üzerinde, mc ile):**
```bash
mc alias set local http://127.0.0.1:9000 <user> <pass>
mc mb local/teqlif
mc mb local/teqlif-dm
mc anonymous set download local/teqlif  # public-read
# ILM (lifecycle) politikaları:
mc ilm add --expiry-days 120 local/teqlif    # listing media 120 gün
mc ilm add --expiry-days 60  local/teqlif-dm # DM media 60 gün
```

### 6.4 node7 — nginx (S3 Proxy)

`media.teqlif.com` (CF Proxied, GET/HEAD, iki katmanlı cache) ve `uploads.teqlif.com` (DNS Only, yazma/presigned GET, cache yok — presigned imza query param içerdiğinden cache güvenlik açığı oluşturur) ayrı `server {}` bloklarında tanımlanır.

```bash
apt-get install -y nginx

# nginx process crash sonrası otomatik kurtarma:
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
systemctl daemon-reload

# nginx SSD cache dizini (root disk /dev/vda3 — 10GB SSD, 1GB cache ayrıl):
mkdir -p /var/cache/nginx/storage
chown www-data:www-data /var/cache/nginx/storage
```

**`/etc/nginx/nginx.conf` — http bloğuna cache zone ekle:**
```nginx
# Proxy cache: SSD üzerinde (root disk) — HDD'ye gitmeden hot dosyaları yakalar
proxy_cache_path /var/cache/nginx/storage
    levels=1:2
    keys_zone=storage_cache:10m
    max_size=1g
    inactive=7d
    use_temp_path=off;
```

**`/etc/nginx/conf.d/minio.conf`:**

İki ayrı domain → iki ayrı server block:
- `media.teqlif.com` — CF **Proxied** (CDN cache): public media GET; CF real_ip; SSD cache; `Cache-Control: public, immutable`
- `uploads.teqlif.com` — **DNS Only** (CF bypass): presigned PUT + DM presigned GET; doğrudan istemci; SSD cache yok; `Cache-Control: no-store`

```nginx
# ── media.teqlif.com — CF Proxied: rate limit gerçek kullanıcı IP'sine ────────
# CF origin hit sayısı düşük (edge cache %90+ karşılar) → yüksek burst toleransı
limit_req_zone  $binary_remote_addr zone=media_req:10m rate=100r/s;

# ── uploads.teqlif.com — DNS Only: doğrudan flood riski ────────────────────────
limit_conn_zone $binary_remote_addr zone=upload_conn:10m;
limit_req_zone  $binary_remote_addr zone=upload_req:10m rate=10r/s;

# ── Upstream Tanımları (Aktif-Aktif HA ve PUT Body Koruma) ──────────────────────
upstream minio_media {
    server 127.0.0.1:9000;
    server 10.10.0.12:9000 backup;  # node8 WireGuard IP
}

upstream minio_uploads {
    server 127.0.0.1:9000;
    server 10.10.0.12:9000 backup;  # node8 WireGuard IP
}

# ── media.teqlif.com HTTP → HTTPS ───────────────────────────────────────────────
server {
    listen 80;
    server_name media.teqlif.com;
    return 301 https://$host$request_uri;
}

# ── media.teqlif.com HTTPS (CF Proxied, public media CDN) ───────────────────────
server {
    listen 443 ssl;
    server_name media.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    # CF Proxied: istemci IP CF-Connecting-IP header'ında gelir
    # set_real_ip_from → $remote_addr = gerçek kullanıcı IP'si → limit_req doğru çalışır
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header    CF-Connecting-IP;
    real_ip_recursive on;

    # GET/HEAD dışını reddet — bu endpoint yalnızca media okuma
    if ($request_method !~ ^(GET|HEAD)$) {
        return 405;
    }

    limit_req zone=media_req burst=200 nodelay;

    # İki katmanlı cache: CF edge (1 ay, Cache Everything page rule) →
    #   CF miss → nginx SSD (7 gün) → MinIO HDD
    # Her iki katman da HDD okuma yükünü azaltır
    proxy_cache         storage_cache;
    proxy_cache_valid   200 7d;
    proxy_cache_methods GET HEAD;
    proxy_cache_use_stale error timeout updating;
    proxy_cache_lock    on;
    proxy_cache_background_update on;
    add_header X-Cache-Status $upstream_cache_status;
    # 1 yıl immutable: MinIO object key içerik değişince değişir, URL asla güncellenmez
    add_header Cache-Control "public, max-age=31536000, immutable";

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        error_page 404 502 503 504 = @media_fallback_node8;
    }

    location @media_fallback_node8 {
        proxy_pass http://10.10.0.12:9000;  # node8 WireGuard IP
        proxy_set_header Host $host;
        proxy_cache_bypass 1;
        proxy_no_cache 1;
    }
}

# ── uploads.teqlif.com HTTP → HTTPS ─────────────────────────────────────────────
server {
    listen 80;
    server_name uploads.teqlif.com;
    return 301 https://$host$request_uri;
}

# ── uploads.teqlif.com HTTPS (DNS Only, presigned PUT + DM GET) ─────────────────
server {
    listen 443 ssl;
    server_name uploads.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    client_max_body_size 100m;   # presigned PUT: büyük video dosyaları
    proxy_read_timeout   300s;
    # proxy_buffering off KULLANMA: buffering kapalıyken proxy_cache çalışmaz (nginx dökümantasyonu).
    # Bu blokta cache zaten kapalı; not bilgi amaçlıdır.

    # DNS Only: doğrudan istemci bağlantısı — flood riski gerçek
    limit_conn upload_conn 10;
    limit_req  zone=upload_req burst=20 nodelay;

    # Presigned URL'ler kullanıcıya özel + zaten DNS Only (CF cache yok)
    # Cache-Control: no-store → tarayıcı da cache'lemesin (DM gizliliği)
    proxy_cache off;
    add_header Cache-Control "no-store";

    location / {
        proxy_pass http://minio_uploads;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}
```

**Cloudflare Origin Certificate:**
```bash
mkdir -p /etc/ssl/teqlif
chmod 700 /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir → kopyala:
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

### 6.5 node8 — MinIO Servisi

node7 ile birebir aynı config; `.env.production`'da yalnızca `EDGE_NODE_ID=node8` farklı.

**`minio.service`:** node7 ile özdeş — aynı `GOMEMLIMIT=2GiB`, `GOGC=100`, `MINIO_API_REQUESTS_MAX=200`.

**Bucket oluşturma:** node7 ile aynı adımlar — dual-write ile her ikisine aynı içerik yazılacak.

### 6.6 node8 — nginx (S3 Proxy + 404 Fallback)

node7 ile aynı kurulum adımları (`apt-get install -y nginx`, cache dizini, nginx.conf proxy_cache_path bloğu).

**`/etc/nginx/conf.d/minio.conf`:** node7 ile aynı yapı; fallback hedefleri ters (`node8 → node7`):

```nginx
limit_req_zone  $binary_remote_addr zone=media_req:10m rate=100r/s;
limit_conn_zone $binary_remote_addr zone=upload_conn:10m;
limit_req_zone  $binary_remote_addr zone=upload_req:10m rate=10r/s;

# ── Upstream Tanımları (Aktif-Aktif HA ve PUT Body Koruma) ──────────────────────
upstream minio_media {
    server 127.0.0.1:9000;
    server 10.10.0.8:9000 backup;  # node7 WireGuard IP
}

upstream minio_uploads {
    server 127.0.0.1:9000;
    server 10.10.0.8:9000 backup;  # node7 WireGuard IP
}

server {
    listen 80;
    server_name media.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name media.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header    CF-Connecting-IP;
    real_ip_recursive on;

    if ($request_method !~ ^(GET|HEAD)$) {
        return 405;
    }

    limit_req zone=media_req burst=200 nodelay;

    proxy_cache         storage_cache;
    proxy_cache_valid   200 7d;
    proxy_cache_methods GET HEAD;
    proxy_cache_use_stale error timeout updating;
    proxy_cache_lock    on;
    proxy_cache_background_update on;
    add_header X-Cache-Status $upstream_cache_status;
    add_header Cache-Control "public, max-age=31536000, immutable";

    location / {
        proxy_pass http://minio_media;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}

server {
    listen 80;
    server_name uploads.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name uploads.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    client_max_body_size 100m;
    proxy_read_timeout   300s;

    limit_conn upload_conn 10;
    limit_req  zone=upload_req burst=20 nodelay;

    proxy_cache off;
    add_header Cache-Control "no-store";

    location / {
        proxy_pass http://minio_uploads;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}
```

### 6.7 teqlif-guardian — node7 + node8

```bash
# Monorepo klon (tüm node'larda aynı):
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
# Storage node — guardian agent için minimal venv (httpx HTTP health check + pyyaml node.conf):
python3 -m venv .venv
.venv/bin/pip install psutil redis httpx pyyaml
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
systemctl enable --now teqlif-guardian
```

### 6.8 Cloudflare DNS — Storage

- [ ] `uploads.teqlif.com` → A → node7 public IP (DNS Only)
- [ ] `uploads.teqlif.com` → A → node8 public IP (DNS Only)
- [ ] `media.teqlif.com`   → A → node7 public IP (Proxied)
- [ ] `media.teqlif.com`   → A → node8 public IP (Proxied)

### 6.9 Storage Senkronizasyon Servisi (node7 ↔ node8)

**Sorun:** Presigned PUT ile doğrudan tek bir node'a yapılan yüklemelerde dosyalar yalnızca o node'da kalır.
**Çözüm:** MinIO Site Replication (Aktif-Aktif) kurulumu. Bu işlem bucket'lar arası asenkron ve sürekli (continuous) replikasyon sağlar. Nightly cron job'ların bıraktığı 24 saatlik veri kaybı penceresini kapatır.

**MinIO Client (`mc`) kurulumu — node5'te (orchestrator ile aynı node):**
```bash
MINIO_RELEASE="RELEASE.2024-11-07T00-52-20Z"   # minio binary ile aynı sürümden mc al
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MINIO_RELEASE}" \
  -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# node7 ve node8'e alias ekle (WireGuard üzerinden):
mc alias set minio7 http://10.10.0.8:9000  <minio_user> <minio_pass>
mc alias set minio8 http://10.10.0.12:9000 <minio_user> <minio_pass>

# Test:
mc admin info minio7
mc admin info minio8
```

**Bucket versioning ve ILM — her iki node'a:**
```bash
# Node7 — versioning etkinleştir:
mc version enable minio7/teqlif
mc version enable minio7/teqlif-dm
# Node8 — versioning etkinleştir:
mc version enable minio8/teqlif
mc version enable minio8/teqlif-dm

# Eski sürümler 90 günde silinsin (disk tasarrufu):
mc ilm rule add --noncurrent-expire-days 90 minio7/teqlif
mc ilm rule add --noncurrent-expire-days 90 minio7/teqlif-dm
mc ilm rule add --noncurrent-expire-days 90 minio8/teqlif
mc ilm rule add --noncurrent-expire-days 90 minio8/teqlif-dm

# Doğrula:
mc version info minio7/teqlif   # → Versioning: enabled
mc version info minio8/teqlif   # → Versioning: enabled
```

**Aktif-Aktif Site Replication (Sürekli Çift Yönlü Senkronizasyon):**

Önkoşul: her iki node'da versioning açık olmalı (yukarıdaki adımda zaten yapıldı).

```bash
# Site Replication kur — her iki node'un MinIO'su çalışıyor olmalı:
mc admin replicate add minio7 minio8

# Her iki yönde aktif olduğunu doğrula:
mc admin replicate info minio7  # → Replication status: Enabled
mc admin replicate info minio8  # → Replication status: Enabled

# Replication test: node7'ye obje yaz, node8'e yansıdı mı?
echo "replication-test" > /tmp/replication-test.txt
mc cp /tmp/replication-test.txt minio7/teqlif/replication-test.txt
sleep 10   # async replikasyon için bekle
mc stat minio8/teqlif/replication-test.txt   # → node7'den replicate edilmeli
mc rm minio7/teqlif/replication-test.txt minio8/teqlif/replication-test.txt

# Bekleyen (henüz replike edilmemiş) obje yok mu?
mc admin replicate diff minio7 minio8   # → boş liste beklenir
```

Site Replication tüm bucket'ları (teqlif, teqlif-dm, teqlif-staging, teqlif-dm-staging) ve IAM politikalarını kapsar. Prometheus zaten MinIO metriklerini scrape ediyor — replication lag `minio_replication_*` metric'leriyle izlenebilir.

**Aylık yetim dosya temizliği — node5'te (§0.3.2'deki `cleanup_orphaned_storage.py` gerektir):**
```bash
cat > /etc/systemd/system/teqlif-storage-cleanup.service << 'EOF'
[Unit]
Description=Monthly MinIO orphaned file cleanup
After=network.target

[Service]
Type=oneshot
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
ExecStart=/var/www/teqlif.com/.venv/bin/python scripts/cleanup_orphaned_storage.py
StandardOutput=append:/var/log/teqlif/storage_cleanup.log
StandardError=append:/var/log/teqlif/storage_cleanup.log
EOF

cat > /etc/systemd/system/teqlif-storage-cleanup.timer << 'EOF'
[Unit]
Description=Monthly MinIO orphaned file cleanup timer

[Timer]
OnCalendar=monthly
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now teqlif-storage-cleanup.timer
# Manuel test:
systemctl start teqlif-storage-cleanup.service
journalctl -u teqlif-storage-cleanup.service -n 20
```

**Logrotate ekle:**
```bash
cat >> /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/storage_cleanup.log {
    monthly
    rotate 12
    compress
    delaycompress
    missingok
}
EOF
```

### 6.10 Faz 6 Doğrulama

```bash
# node7
curl -I http://10.10.0.8:9000/minio/health/live     # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node7  # → Hash alanları

# node8
curl -I http://10.10.0.12:9000/minio/health/live    # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node8  # → Hash alanları

# DNS
dig uploads.teqlif.com +short  # iki IP dönmeli
dig media.teqlif.com +short    # iki IP dönmeli

# nginx fallback testi — port 9000 (MinIO doğrudan) değil, nginx üzerinden test edilmeli:
# 1. Test objesi oluştur — sadece node7'ye yükle:
mc cp /tmp/test-fallback.txt minio7/teqlif/test-fallback.txt

# 2. node8 nginx üzerinden eriş (port 80) — node8 MinIO'da yok → @fallback_node7 tetiklenmeli:
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: uploads.teqlif.com" http://10.10.0.12:80/teqlif/test-fallback.txt
# → 200 (node8 nginx → node7 MinIO fallback)

# 3. node7 nginx üzerinden aynı mantıkla ters test (node8'e özgü bir obje):
mc cp /tmp/test-fallback2.txt minio8/teqlif/test-fallback2.txt
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: uploads.teqlif.com" http://10.10.0.8:80/teqlif/test-fallback2.txt
# → 200 (node7 nginx → node8 MinIO fallback)

# Site Replication aktif mi?
mc admin replicate info minio7   # → Replication status: Enabled
mc admin replicate diff minio7 minio8   # → boş liste
```

---

## Faz 7 — Gateway (gateway1 + gateway2)

**Önkoşul:** Faz 5 tamamlandı. (Guardian ve diğer bağımlılıklar için Veri Katmanı / Redis VIP hazır olmalıdır.)

### 7.1 nginx Kurulumu

```bash
apt-get install -y nginx

# nginx process crash sonrası otomatik kurtarma — paket varsayılanı Restart=on-failure, bu yetmez
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
systemctl daemon-reload
```

**`/etc/nginx/nginx.conf` — worker ayarları:**
```nginx
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;

    server_tokens off;

    gzip on;
    gzip_types text/plain application/json application/javascript text/css;
    gzip_min_length 1000;

    # Gerçek client IP (CF proxy arkasında) — limit_req $binary_remote_addr CF IP'si değil gerçek kullanıcı IP'si olsun:
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header CF-Connecting-IP;
    real_ip_recursive on;

    # Rate limiting — http bloğunda tanımlanmalı, server içinde değil:
    limit_req_zone  $binary_remote_addr zone=api_limit:10m rate=30r/s;
    # Bağlantı limiti (connection exhaustion saldırısı engeli):
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # WebSocket upgrade map — Connection header'ı doğru set eder;
    # global "upgrade" ayarı upstream keepalive'ı kırar.
    # ÖNEMLI: '' için "close" DEĞİL "" (boş) kullanılmalı —
    # "close" göndermek upstream keepalive'ı kırar; boş → header silinir → keepalive çalışır:
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      '';
    }

    include /etc/nginx/conf.d/*.conf;
}
```

**`/etc/nginx/conf.d/teqlif.conf`:**
```nginx
upstream teqlif_core {
    server 10.10.0.5:8000 max_fails=3 fail_timeout=10s;   # node5 (primary)
    server 10.10.0.7:8000 backup max_fails=1 fail_timeout=10s;
    # ↑ node6 standby: node5 down olduğunda nginx buraya geçer.
    # Ancak node6'daki teqlif servisleri failover tamamlanana kadar kapalıdır.
    # Bu pencerede (~15-30s) node6'ya gelen istekler 502 döner — nginx bunu passive olarak öğrenir.
    # Kabul edilebilir: aktif-pasif HA tasarımında sıfır downtime garanti edilmez, kısa kesinti beklenir.
    keepalive 32;
}

server {
    listen 443 ssl;
    server_name api.teqlif.com teqlif.com www.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;  # map üzerinden — WS için upgrade, diğerleri için close

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-For   $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_connect_timeout 5s;
    proxy_read_timeout    300s;

    # Güvenlik headerları (CF proxy arkasında çalışır — HSTS CF seviyesinde de açık olmalı §0.11)
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), microphone=(), camera=()" always;

    # Bağlantı limiti — tek IP'den max 100 eşzamanlı bağlantı
    # CGNAT: mobil operatörlerde birden fazla kullanıcı aynı IP'yi paylaşır; 50 dar kalır
    limit_conn conn_limit 100;

    # V2.0 yeşil alan: presigned upload tek yöntem, gateway sadece JSON/API taşır
    client_max_body_size 5m;

    # WS: /api/messages/ws — daha spesifik eşleşme /api/'dan önce gelir
    # ws_service.dart: wss://api.teqlif.com/api/messages/ws — /ws/ path'i HİÇBİR ZAMAN eşleşmez
    location /api/messages/ws {
        proxy_pass http://teqlif_core;
        proxy_read_timeout 3600s;  # WS — 1 saat; client 25s ping gönderir
        # CGNAT: 20 → aynı IP'den birden fazla kullanıcının WS bağlantısı için yeterli
        limit_conn conn_limit 20;
    }

    location /api/ {
        limit_req zone=api_limit burst=60 nodelay;
        proxy_pass http://teqlif_core;
    }

    location / {
        proxy_pass http://teqlif_core;
    }
}

server {
    listen 80;
    server_name api.teqlif.com teqlif.com www.teqlif.com;
    return 301 https://$host$request_uri;
}

# Staging — node3'e WireGuard üzerinden yönlendir
upstream teqlif_staging {
    server 10.10.0.4:8000;
    keepalive 8;
}

server {
    listen 443 ssl;
    server_name staging.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-For   $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout    300s;

    # Staging — tüm trafik node3'e
    location / {
        proxy_pass http://teqlif_staging;
    }
}

server {
    listen 80;
    server_name staging.teqlif.com;
    return 301 https://$host$request_uri;
}
```

### 7.2 Cloudflare Origin Certificate

```bash
mkdir -p /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir (.pem formatı)
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

### 7.3 Guardian Metrics + Promtail

> **Not:** `node_exporter` kurulmaz. `teqlif-guardian.service`, port **:9200**'de `prometheus_client` ile `/metrics` endpoint'i sunar; `node_cpu_seconds_total`, `node_filesystem_*`, `node_memory_*`, `node_systemd_unit_state` gibi node-exporter uyumlu metrik isimleri kullanır. Böylece ayrı bir binary gerekmez. Implement: `backend/scripts/guardian_agent.py` (bkz. §0.2.2).

#### Promtail

```bash
# Tüm node'larda — Grafana apt reposu ekle (node9'da Faz 10'da zaten yapılır):
apt-get install -y apt-transport-https software-properties-common
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor \
  | tee /usr/share/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y promtail
```

**`/etc/promtail/config.yml`** — `<NODE_ID>` ve `<NODE_WG_IP>` yerine o node'un değerleri:
```yaml
server:
  http_listen_port: 0   # scraping-only; HTTP endpoint kapalı
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://10.10.0.13:3100/loki/api/v1/push  # node9 Loki

scrape_configs:
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      labels:
        job: journal
        node: <NODE_ID>   # örn. gateway1, node5, node7
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: unit
      - source_labels: [__journal_priority_keyword]
        target_label: level

  - job_name: teqlif_file_logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: teqlif
          node: <NODE_ID>
          __path__: /var/log/teqlif/**   # ** recursive: api/, worker/, orchestrator/ + top-level backup log'ları
```

```bash
mkdir -p /var/lib/promtail

# Promtail systemd override — journal + file log okuma için grup üyeliği:
# systemd-journal: journal socket okuma yetkisi
# adm: geleneksel /var/log erişim grubu (Debian/Ubuntu)
mkdir -p /etc/systemd/system/promtail.service.d
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/promtail.service.d/override.conf \
   /etc/systemd/system/promtail.service.d/override.conf
systemctl daemon-reload
systemctl enable --now promtail
# Doğrula:
journalctl -u promtail -n 20
```

### 7.4 Cloudflare DNS — Gateway

- [ ] `teqlif.com`     → A → gateway1 public IP (Proxied)
- [ ] `teqlif.com`     → A → gateway2 public IP (Proxied)
- [ ] `api.teqlif.com` → A → gateway1 public IP (Proxied)
- [ ] `api.teqlif.com` → A → gateway2 public IP (Proxied)

### 7.5 teqlif-guardian — gateway1 + gateway2

```bash
# Monorepo klon (tüm node'larda aynı):
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
# Gateway node — guardian agent için minimal venv (httpx HTTP health check + pyyaml node.conf):
python3 -m venv .venv
.venv/bin/pip install psutil redis httpx pyyaml
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/gateway1/resources/.env.production.template \
   /etc/teqlif/.env.production   # gateway2 için gateway2 template'i
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
systemctl enable --now teqlif-guardian

# Doğrula:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:gateway1
# primary_role, net_out_percent, cpu_percent alanları görünmeli
```

### 7.6 Faz 7 Doğrulama

```bash
nginx -t && systemctl reload nginx
curl -I https://api.teqlif.com/health  # → 200
dig api.teqlif.com +short             # iki IP dönmeli
```

---

## Faz 8 — Stream + AI Proxy

**Önkoşul:** Faz 5 tamamlandı. (LiveKit, AI Proxy ve Guardian için Veri Katmanı / Redis VIP hazır olmalıdır.)

### 8.1 LiveKit SFU — node1 ve node4

**Monorepo + venv (node1 ve node4'te aynı adımlar):**
```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install psutil redis httpx pyyaml   # guardian agent için
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

# node1 için:
cp /var/www/teqlif.com/deploy/scale/V2.0/node1/resources/.env.production.template \
   /etc/teqlif/.env.production
# node4 için: deploy/scale/V2.0/node4/resources/.env.production.template kullan
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**Kurulum:**
```bash
# Pinned release — latest kullanma; https://github.com/livekit/livekit/releases adresinden kontrol et
LIVEKIT_VER="1.8.3"
curl -fsSL "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VER}/livekit_${LIVEKIT_VER}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin/ livekit-server
livekit-server version  # doğrula
```

```bash
mkdir -p /etc/livekit
chmod 700 /etc/livekit
```

**`/etc/livekit/livekit.yaml`:**
```yaml
port: 7880
bind_addresses:
  - ""  # tüm arayüzler
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
  ice_lite: false

turn:
  enabled: true
  domain: live1.teqlif.com  # node4 için: live2.teqlif.com
  tls_port: 5349
  udp_port: 3478
  relay_range_start: 50000  # UFW'de açık aralıkla eşleşmeli: 50000:60000/udp
  relay_range_end: 60000
  # external_tls: true KULLANMA — önünde TLS proxy olmadan port 5349 plain TCP dinler ve çalışmaz.
  # CF Origin Cert *.teqlif.com kapsıyor; LiveKit bu cert'i doğrudan kullanır:
  cert_file: /etc/ssl/teqlif/cf-origin.crt
  key_file:  /etc/ssl/teqlif/cf-origin.key

redis:
  address: 10.10.0.11:6379     # Core Redis — kalıcı; Orch Redis (6380) persistence'sız olduğu için uygun değil
  db: 1                        # DB 1 — app DB 0 ile çakışmaz
  password: <core_redis_pass>

keys:
  <livekit_api_key>: <livekit_api_secret>

logging:
  level: info
  json: true
```

**`/etc/systemd/system/livekit.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node1/systemd/livekit.service \
   /etc/systemd/system/livekit.service
# node4'te: node4/systemd/livekit.service (özdeş içerik)
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
systemctl enable --now livekit teqlif-guardian
```

**Cloudflare DNS:**
- [ ] `live1.teqlif.com` → A → node1 public IP (DNS Only — WebRTC UDP için proxy olmamalı)
- [ ] `live2.teqlif.com` → A → node4 public IP (DNS Only)

### 8.2 AI Proxy — node2

```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/node2/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/systemd/system/teqlif-ai-proxy.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node2/systemd/teqlif-ai-proxy.service \
   /etc/systemd/system/teqlif-ai-proxy.service
```

### 8.3 teqlif-guardian — node2

```bash
# node2'de monorepo zaten 8.2'de klonlandı (/var/www/teqlif.com).
# full requirements.txt psutil+redis+httpx+pyyaml içerir — ek paket gerekmez.
```

**`/etc/teqlif/.env.production` (node2 ek alanları — Faz 0.5'ten template'e eklendi):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node2
NODE_ROLE=ai_proxy
NODE_CAPABILITIES=["ai_proxy"]
INTERFACE_SPEED_MBPS=300
DATA_DISK_PATH=/
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
systemctl enable --now teqlif-ai-proxy teqlif-guardian
```

### 8.4 Faz 8 Doğrulama

```bash
# node1
curl -s http://10.10.0.1:7880/  # → LiveKit info JSON
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node1  # → Hash alanları

# node2
curl -s http://10.10.0.3:8001/health  # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node2  # → Hash alanları

# node4
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node4  # → Hash alanları
```

### 8.5 AI Proxy Fallback — node3 (İlk Yedek)

node3 AI proxy'yi **her zaman çalışır** durumda tutar — node2 düştüğünde orchestrator zaten aktif bir süreci hedef alır, başlatma gecikmesi olmaz. node5'ten farklı olarak `enable` edilir.

```bash
# node3'te — monorepo ve venv §10.1'de kurulur; bu adım §10.1 sonrasına yerleştirilmeli
# ama servis dosyasını §8 sırasında ya da §10 içinde kurabilirsin — bağımlılık yok.
```

**`/etc/systemd/system/teqlif-ai-proxy.service` (node3):**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-ai-proxy.service \
   /etc/systemd/system/teqlif-ai-proxy.service
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif-ai-proxy
# node3 her zaman çalışır ama ai_proxy:active_url=node2 olduğu sürece trafik almaz
# Orchestrator node2 down → node3'ü hedef alır, ai_proxy:active_url=http://10.10.0.4:8001 yazar
```

**Faz 8.5 Doğrulama:**
```bash
# node3 AI proxy ayakta mı?
curl -s http://10.10.0.4:8001/health  # → 200

# Orchestrator henüz ai_proxy:active_url yazmadıysa default (node2) kullanılır:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url  # → (nil) veya http://10.10.0.3:8001
```

---

## Faz 9 — Guardian Koordinatör

**Önkoşul:** Faz 5 (Core App) + Faz 6 (Storage) + Faz 7 (Gateway) + Faz 8 (Stream) tamamlandı.

### 9.1 Guardian Agent (Metrik) Doğrulaması

```bash
# Tüm 10 node için metrik var mı?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"
# → edge:metrics:gateway1, gateway2, node1 ... node8 (10 anahtar)

# edge:metrics Hash tipi olmalı (JSON String değil):
redis-cli -h 10.10.0.11 -p 6380 -a <pass> type edge:metrics:node7
# → hash

# node7 ve node8 disk_free_gb doğru mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hget edge:metrics:node7 disk_free_gb
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hget edge:metrics:node8 disk_free_gb

# Tüm alanlar (20+ alan beklenir):
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node7
```

### 9.2 Guardian Aktif mi + AI Proxy Routing Doğrulama

```bash
# Guardian agent tüm node'larda çalışıyor mu?
systemctl is-active teqlif-guardian  # → active

# AI proxy: node2 sağlıklıysa key yoktur (uygulama config default'u kullanır) veya node2 URL'si:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → (nil) veya http://10.10.0.3:8001   (node2 aktif = normal durum)

# node2 edge:metrics TTL var mı? (6s TTL, yoksa node2 down sayılır)
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node2  # → 1-6 arası
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node3  # → 1-6 arası
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node5  # → 1-6 arası
```

### 9.3 Dual-Write Routing Doğrulama

```bash
# Orchestrator storage_nodes yazıyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7","node8"]  (her ikisi sağlıklı)

# Bir test dosyası yükle (node5 API üzerinden):
curl -X POST http://127.0.0.1:8000/test/upload -F "file=@/tmp/test.jpg"

# Her iki storage node'da dosya var mı?
mc ls local/teqlif/<key>  # node7'de
# node8'de de aynı komut
```

### 9.4 Failover Simülasyonu — Storage

```bash
# node8 MinIO durdur:
ssh node8 "systemctl stop minio"

# Orchestrator fark etmeli (~6s):
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7"]

# DNS güncellemesi (~30s CF TTL sonrası):
dig uploads.teqlif.com +short  # sadece node7 IP görünmeli

# Telegram #ops bildirimi geldi mi?
# node8'i yeniden başlat ve recovery'yi doğrula
ssh node8 "systemctl start minio"
sleep 15
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7","node8"]
```

### 9.5 Failover Simülasyonu — AI Proxy

```bash
# node2 teqlif-ai-proxy durdur (node2 tamamen down gibi davranır):
ssh tucibeyin@10.10.0.3 "sudo systemctl stop teqlif-ai-proxy teqlif-guardian"

# Orchestrator edge:metrics:node2 TTL'si dolar → ~6s içinde node3'e geçiş:
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → http://10.10.0.4:8001  (node3)

# Uygulama AI proxy'yi node3 üzerinden kullanıyor mu?
curl -s http://127.0.0.1:8000/api/test/ai-call  # → 200, AI yanıtı

# node2'yi geri getir ve failback doğrula (otomatik):
ssh tucibeyin@10.10.0.3 "sudo systemctl start teqlif-ai-proxy teqlif-guardian"
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → http://10.10.0.3:8001  (node2 — otomatik failback)

# node3 + node5 ikisi de down olursa node5 devreye girer:
# systemctl start teqlif-ai-proxy  ← orchestrator node5'te bunu tetikler, sonra URL'yi günceller
```

---

## Faz 10 — Monitoring + Backup + ClickHouse (node9)

**Önkoşul:** Faz 9 tamamlandı.

> **node9 kurulum sırası:** §10.0 → §10.1 → §10.2 → §10.3 → §10.4 → §10.5 → §10.6 → §10.7 doğrulama.
> Faz 1 (OS temeli), Faz 2 (WireGuard), §3.5 (OS tuning) node9 için de uygulanır — §10.0 bu adımları takip eder.

### 10.0 node9 Ön Kurulum (OS + /data + WireGuard)

#### 10.0.1 OS Temeli

**NOT:** node9 OS temel kurulumu (Faz 1) ve WireGuard mesh (Faz 2) tüm node'larla birlikte zaten tamamlandı. Bu adımda node9'a özgü ekstra dizin ve tuning işlemleri (ClickHouse/Loki için) yapılır:

```bash
# §1.9 Swap Dosyası — node9: /data üzerinde HDD, büyük swap OK
# Mevcut kurulumda sda4 swap=512MB (OVH partition). İsteğe bağlı olarak genişletilebilir:
# swapoff /dev/md_swap
# mkswap /dev/md_swap  # veya /data altında dosya-based swap
# Şimdilik 512 MB yeterli — node9 prod trafik almaz

# §1.3 Dizin yapısı — node9 ekstra:
mkdir -p /data/clickhouse/{data,tmp,backups,logs}
mkdir -p /data/loki/{chunks,rules,compactor}
mkdir -p /data/prometheus
# PG WAL/backup 3.5TB /data diskine yazılır — root dolmaz:
mkdir -p /data/teqlif_backups/{postgres/{wal,basebackup,dump},redis,offsite-log}
mkdir -p /opt/teqlif/scripts
mkdir -p /var/log/teqlif

chown clickhouse:clickhouse /data/clickhouse /data/clickhouse/data \
  /data/clickhouse/tmp /data/clickhouse/backups /data/clickhouse/logs
chmod 750 /data/clickhouse /data/clickhouse/data \
  /data/clickhouse/tmp /data/clickhouse/backups

chown loki:loki /data/loki /data/loki/chunks /data/loki/rules /data/loki/compactor
chown prometheus:prometheus /data/prometheus
chown -R tucibeyin:tucibeyin /data/teqlif_backups /opt/teqlif /var/log/teqlif
chmod 700 /data/teqlif_backups
chmod 750 /opt/teqlif/scripts
chmod 755 /var/log/teqlif
ln -s /data/teqlif_backups /opt/teqlif/backups   # tüm script'ler /opt/teqlif/backups/ yolunu kullanır
```

#### 10.0.2 OS Tuning (node9'a özgü)

§3.5'in node9 bloğu (sysctl + UFW) burada uygulanır.

**Sysctl — node9:**
```bash
cat > /etc/sysctl.d/99-teqlif.conf << 'EOF'
vm.swappiness = 5
fs.file-max = 131072
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.overcommit_memory = 1          # Prometheus + Loki mmap için
# HDD RAID-1: I/O scheduler deadline performansı artırır (blk-mq için mq-deadline)
EOF
sysctl -p /etc/sysctl.d/99-teqlif.conf

# HDD I/O scheduler — her iki disk için
for disk in sda sdb; do
  echo mq-deadline > /sys/block/${disk}/queue/scheduler
  # Persist:
  echo 'ACTION=="add|change", KERNEL=="sd[ab]", ATTR{queue/scheduler}="mq-deadline"' \
    >> /etc/udev/rules.d/99-teqlif-io.rules
done
```

**UFW — node9:**
```bash
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24   # mesh: ClickHouse, Prometheus, Loki, Grafana
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Grafana, Prometheus, Loki sadece WG üzerinden — dışarıya AÇILMAZ
ufw --force enable
```

**LimitNOFILE — node9 (ClickHouse + Loki için):**
```bash
# ClickHouse servis override:
mkdir -p /etc/systemd/system/clickhouse-server.service.d
cat > /etc/systemd/system/clickhouse-server.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=262144
EOF
# Loki servis override:
mkdir -p /etc/systemd/system/loki.service.d
cat > /etc/systemd/system/loki.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65536
EOF
systemctl daemon-reload
```

#### 10.0.3 WireGuard — node9

node9 ağ mesh'e dahil edilir. Diğer tüm node'larda node9 peer zaten WG template'e eklendi (§2.2). Burada node9'un kendi wg0.conf'u kurulur ve mesh'e tanıtılır.

**node9 wg0.conf şablonu:**
```ini
# /etc/wireguard/wg0.conf — node9
[Interface]
PrivateKey = <node9_private_key>
Address = 10.10.0.13/24
ListenPort = 51820
MTU = 1420

# gateway1
[Peer]
PublicKey = <gateway1_pubkey>
AllowedIPs = 10.10.0.2/32
Endpoint = <gateway1_public_ip>:51820
PersistentKeepalive = 25

# gateway2
[Peer]
PublicKey = <gateway2_pubkey>
AllowedIPs = 10.10.0.9/32
Endpoint = <gateway2_public_ip>:51820
PersistentKeepalive = 25

# node1
[Peer]
PublicKey = <node1_pubkey>
AllowedIPs = 10.10.0.1/32
Endpoint = <node1_public_ip>:51820
PersistentKeepalive = 25

# node2
[Peer]
PublicKey = <node2_pubkey>
AllowedIPs = 10.10.0.3/32
Endpoint = <node2_public_ip>:51820
PersistentKeepalive = 25

# node3
[Peer]
PublicKey = <node3_pubkey>
AllowedIPs = 10.10.0.4/32
Endpoint = <node3_public_ip>:51820
PersistentKeepalive = 25

# node4
[Peer]
PublicKey = <node4_pubkey>
AllowedIPs = 10.10.0.6/32
Endpoint = <node4_public_ip>:51820
PersistentKeepalive = 25

# node5 — core (VIP'ler dahil)
[Peer]
PublicKey = <node5_pubkey>
AllowedIPs = 10.10.0.5/32,10.10.0.10/32,10.10.0.11/32
Endpoint = <node5_public_ip>:51820
PersistentKeepalive = 25

# node6 — standby (VIP'ler devralabilir)
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node7
[Peer]
PublicKey = <node7_pubkey>
AllowedIPs = 10.10.0.8/32
Endpoint = <node7_public_ip>:51820
PersistentKeepalive = 25

# node8
[Peer]
PublicKey = <node8_pubkey>
AllowedIPs = 10.10.0.12/32
Endpoint = <node8_public_ip>:51820
PersistentKeepalive = 25
```

```bash
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0

# Mesh doğrulama — tüm node'lara ping:
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 \
          10.10.0.6 10.10.0.7 10.10.0.8 10.10.0.9 10.10.0.12; do
  ping -c1 -W2 "${ip}" > /dev/null && echo "OK: ${ip}" || echo "FAIL: ${ip}"
done
# → Tüm node'lar OK

# Diğer node'larda node9 peer'ı ekle — her node'da çalıştır:
# (§2.2 template'inde zaten var; kurulmamış node'larda wg set ile hot-add:)
# wg set wg0 peer <node9_pubkey> allowed-ips 10.10.0.13/32 \
#   endpoint <node9_public_ip>:51820 persistent-keepalive 25
# wg-quick save wg0
```

#### 10.0.4 node.conf + .env.production

```bash
mkdir -p /etc/teqlif
# node9 node.conf — §1.4'teki node9 şablonu kullan
cat > /etc/teqlif/node.conf << 'EOF'
# (§1.4 node9 node.conf içeriği buraya yapıştırılır)
EOF
chmod 644 /etc/teqlif/node.conf

# .env.production — §0.5 node9 template'i kullan
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production

# Doğrula:
python3 -c "import yaml; c=yaml.safe_load(open('/etc/teqlif/node.conf')); print(c['node_id'], c['env'])"
# → node9 production
```

#### 10.0.5 ClickHouse Kurulumu

§4.8'deki tüm komutları bu aşamada çalıştır:
- APT repo ekle + `clickhouse-server clickhouse-client` kur
- `/etc/clickhouse-server/config.d/teqlif.xml` oluştur
- `/etc/clickhouse-server/users.d/teqlif.xml` oluştur
- `systemctl enable --now clickhouse-server`
- Schema'yı yükle: `clickhouse-client ... < backend/db/clickhouse_schema.sql`

```bash
# Doğrula:
clickhouse-client --user=teqlif --password=<pass> \
  --query="SELECT count() FROM system.tables WHERE database='teqlif'"
# → tablo sayısı (0 veya daha fazla)
curl -s "http://10.10.0.13:8123/?query=SELECT+1" --user teqlif:<pass>
# → 1
```

#### 10.0.4 ClickHouse — node9

> **V2.0 mimarisi:** ClickHouse node5'ten node9'a taşındı. node5/6 ClickHouse'dan tamamen bağımsız — failover karmaşıklığı azaldı, node5 ~500 MB RAM serbest kaldı. App WireGuard üzerinden `10.10.0.13:8123`'e bağlanır.

```bash
apt-get install -y apt-transport-https ca-certificates gnupg

# ClickHouse resmi Debian APT reposu:
curl -fsSL 'https://packages.clickhouse.com/deb/clickhouse.gpg' \
  | gpg --dearmor > /usr/share/keyrings/clickhouse-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] \
  https://packages.clickhouse.com/deb/ stable main" \
  > /etc/apt/sources.list.d/clickhouse.list

apt-get update
apt-get install -y clickhouse-server clickhouse-client
```

**`/etc/clickhouse-server/config.d/teqlif.xml`:**
```xml
<clickhouse>
  <listen_host>127.0.0.1</listen_host>
  <listen_host>10.10.0.13</listen_host>  <!-- node9 WG IP — tüm mesh node'ları buraya bağlanır -->
  <max_connections>100</max_connections>
  <!-- Sunucu düzeyinde mutlak bellek tavanı — query limit'lerin (users.d) üstünde background merge/compaction dahil tüm CH belleği kapsar -->
  <!-- node9: 31 GB RAM; CH 24 GB, kalan 7 GB Prometheus + Loki + OS page cache için -->
  <max_server_memory_usage>25769803776</max_server_memory_usage>  <!-- 24 GB -->
  <!-- Data dizini — node9 /data partition'ında; 3.5 TB HDD RAID-1 -->
  <path>/data/clickhouse/</path>
  <tmp_path>/data/clickhouse/tmp/</tmp_path>
  <!-- Backup disk — yerel backup, ayrıca offsite'a gönderilir -->
  <storage_configuration>
    <disks>
      <backups>
        <type>local</type>
        <path>/data/clickhouse/backups/</path>
      </backups>
    </disks>
  </storage_configuration>
  <backups>
    <allowed_disk>backups</allowed_disk>
  </backups>
</clickhouse>
```

**`/etc/clickhouse-server/users.d/teqlif.xml` — kullanıcı tanımları + bellek sınırı:**
```xml
<clickhouse>
  <!-- default user: şifreli, sadece localhost, backup erişimi yok -->
  <users>
    <default>
      <password_sha256_hex><default_user_sha256></password_sha256_hex>
      <networks>
        <ip>127.0.0.1</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
    </default>

    <!-- uygulama kullanıcısı: WG ağından erişebilir -->
    <teqlif>
      <password_sha256_hex><teqlif_ch_sha256></password_sha256_hex>
      <networks>
        <ip>127.0.0.1</ip>
        <ip>10.10.0.0/24</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
      <allow_databases>
        <database>teqlif</database>
      </allow_databases>
    </teqlif>
  </users>

  <!-- Bellek sınırı — node9: 31 GB RAM, ClickHouse + Prometheus + Loki paylaşımlı -->
  <!-- ClickHouse: 12 GB | Prometheus: 4 GB | Loki: 6 GB | OS+diğer: ~9 GB -->
  <profiles>
    <default>
      <max_memory_usage>8000000000</max_memory_usage>        <!-- 8 GB tek sorgu limiti -->
      <max_memory_usage_for_all_queries>12000000000</max_memory_usage_for_all_queries>  <!-- 12 GB toplam -->
      <!-- Background merge kısıtı — gece backup ile çakışmasın -->
      <background_pool_size>2</background_pool_size>
      <background_merges_mutations_concurrency_ratio>1</background_merges_mutations_concurrency_ratio>
    </default>
  </profiles>
</clickhouse>
```

```bash
# SHA256 hash üretimi (kurulum sırasında yapılır):
# echo -n "<teqlif_ch_password>" | sha256sum
# Üretilen hash'i teqlif.xml'deki <teqlif_ch_sha256> yerine yaz

# Backup dizini node9'da /data/clickhouse/backups/ altında — bkz. §4.8 ClickHouse konfigürasyonu.
# node9 lokal backup: SSH/rsync veya sudoers gerekmez.

systemctl enable --now clickhouse-server
# Şema oluştur (teqlif kullanıcısıyla):
clickhouse-client --user=teqlif --password=<teqlif_ch_password> \
  < backend/db/clickhouse_schema.sql
# Doğrula:
clickhouse-client --user=teqlif --password=<teqlif_ch_password> \
  --query="SELECT count() FROM system.tables WHERE database='teqlif'"
```


### 10.1 teqlif-guardian — node9

```bash
# Monorepo klonla — full venv (node9 guardian agent + ClickHouse ikisi de bu venv'i kullanır)
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt   # full
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/node9/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/teqlif/.env.production` (node9 ek alanları — Faz 0.5'ten template'e eklendi):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
GUARDIAN_REDIS_URL=redis://:<guardian_redis_pass>@10.10.0.11:6382/0
EDGE_NODE_ID=node9
NODE_ROLE=monitor
NODE_CAPABILITIES=["monitor","backup","clickhouse"]
INTERFACE_SPEED_MBPS=480
DATA_DISK_PATH=/data
# Backup scriptleri için:
CORE_REDIS_PASS=<core_redis_pass>
PG_PASSWORD=<teqlif_db_password>
REPLICATOR_PASSWORD=<replicator_password>
CLICKHOUSE_HOST=127.0.0.1
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID_OPS=<telegram_chat_id_ops>
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
systemctl daemon-reload
systemctl enable --now teqlif-guardian
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node9  # → Hash alanları
```

### 10.2 Prometheus

```bash
apt-get install -y prometheus

# TSDB retention + bellek optimizasyonu (node9: 31GB RAM, Grafana + Loki + ClickHouse ile paylaşımlı):
mkdir -p /etc/systemd/system/prometheus.service.d
cat > /etc/systemd/system/prometheus.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/data \
  --storage.tsdb.retention.time=30d \
  --storage.tsdb.wal-compression \
  --web.enable-lifecycle \
  --storage.tsdb.max-block-duration=2h
EOF
systemctl daemon-reload
```

**`/etc/prometheus/prometheus.yml` — scrape config + alertmanager:**
```yaml
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - '127.0.0.1:9093'   # Alertmanager aynı node'da (node9)

rule_files:
  - /etc/prometheus/alert_rules.yml

scrape_configs:
  # node-exporter YOK — guardian_agent.py :9200/metrics endpoint'i node-exporter uyumlu metrikler sunar
  - job_name: 'teqlif_guardian'
    static_configs:
      - targets:
        - '10.10.0.1:9200'   # gateway1
        - '10.10.0.2:9200'   # gateway2
        - '10.10.0.3:9200'   # node2 (AI Proxy)
        - '10.10.0.4:9200'   # node3 (Staging)
        - '10.10.0.5:9200'   # node5 (Core)
        - '10.10.0.6:9200'   # node6 (Core)
        - '10.10.0.7:9200'   # node7 (Storage)
        - '10.10.0.8:9200'   # node8 (Storage)
        - '10.10.0.9:9200'   # node1 (Stream)
        - '10.10.0.12:9200'  # node4 (Stream)
        - '10.10.0.13:9200'  # node9 (Sistem Full Backup/Monitor/ClickHouse)
```

**`/etc/prometheus/alert_rules.yml`:**
```yaml
groups:
  - name: teqlif_infra
    rules:
      - alert: NodeDown
        # Gateway (2,9) ve storage (8,12) node'ları hariç — bunların kendi özel alert'leri var (GatewayDown/StorageNodeDown).
        expr: up{job="teqlif_guardian", instance!~"10\\.10\\.0\\.(2|9|8|12):9200"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          description: "Guardian agent {{ $labels.instance }} has been down for 2+ minutes."

      - alert: StorageNodeDown
        expr: up{job="teqlif_guardian", instance=~"10\\.10\\.0\\.(8|12):9200"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Storage node {{ $labels.instance }} unreachable"
          description: "MinIO storage node {{ $labels.instance }} is down."

      - alert: Node5HighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle",instance="10.10.0.5:9200"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "node5 CPU {{ $value | printf \"%.1f\" }}% > 85%"

      - alert: StorageDiskHigh
        expr: (node_filesystem_size_bytes{instance=~"10\\.10\\.0\\.(7|8):9200",mountpoint="/mnt/data"} - node_filesystem_free_bytes{instance=~"10\\.10\\.0\\.(7|8):9200",mountpoint="/mnt/data"}) / node_filesystem_size_bytes{instance=~"10\\.10\\.0\\.(7|8):9200",mountpoint="/mnt/data"} * 100 > 85
        for: 10m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "Storage {{ $labels.instance }} disk doluluk: {{ $value | printf \"%.1f\" }}%"

      - alert: GatewayDown
        expr: up{job="teqlif_guardian", instance=~"10\\.10\\.0\\.(1|2):9200"} == 0
        for: 30s
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "Gateway {{ $labels.instance }} erişilemiyor — trafik tek gateway'e düşüyor."

      # node9 disk: backup + WAL + Loki + ClickHouse verileri /data'yı doldurabilir
      - alert: MonitorDiskHigh
        expr: (node_filesystem_size_bytes{instance="10.10.0.13:9200",mountpoint="/data"} - node_filesystem_free_bytes{instance="10.10.0.13:9200",mountpoint="/data"}) / node_filesystem_size_bytes{instance="10.10.0.13:9200",mountpoint="/data"} * 100 > 80
        for: 10m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "node9 (monitor/backup) disk doluluk: {{ $value | printf \"%.1f\" }}% — backup ve WAL temizlenmeli."

      # Servis crash loop koruması: "failed" state Prometheus'ta up=0 göstermez,
      # node_systemd_unit_state ile izlenir (guardian_agent.py prometheus_client ile sunar)
      - alert: ServiceFailed
        expr: node_systemd_unit_state{name=~"teqlif.*\\.service",state="failed"} == 1
        for: 1m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "{{ $labels.instance }} — {{ $labels.name }} failed state: StartLimitBurst aşıldı, manuel müdahale gerekli."
```

**postgres_exporter (node5) — replica lag + DB metrikleri:**

node5'te kurulur; node9 Prometheus'u `10.10.0.5:9187`'yi scrape eder (bkz. §10.1 scrape_configs ve alert_rules.yml — aşağıya PostgreSQLReplicaLag kuralı eklendi).

```bash
# node5'te:
PG_EXPORTER_VER="0.15.0"
curl -fsSL "https://github.com/prometheus-community/postgres_exporter/releases/download/v${PG_EXPORTER_VER}/postgres_exporter-${PG_EXPORTER_VER}.linux-amd64.tar.gz" \
  | tar -xz -C /usr/local/bin --strip-components=1 \
    postgres_exporter-${PG_EXPORTER_VER}.linux-amd64/postgres_exporter
```

**`/etc/systemd/system/postgres-exporter.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/systemd/postgres-exporter.service \
   /etc/systemd/system/postgres-exporter.service
```

> `DATA_SOURCE_NAME` `.env.production` içinde tanımlanır (aşağıya bakın). `Environment=` satırında parola olmasın — `systemctl show` çıktısında görünür.

```bash
systemctl enable --now postgres-exporter
```

**Prometheus scrape_configs'e ekle** (`/etc/prometheus/prometheus.yml`, node9):
```yaml
  - job_name: 'postgres'
    static_configs:
      - targets:
          - '10.10.0.5:9187'   # node5 postgres_exporter
```

**alert_rules.yml'e ekle:**
```yaml
      - alert: PostgreSQLReplicaLag
        expr: pg_stat_replication_pg_wal_lsn_diff{application_name="walreceiver"} > 10485760
        for: 1m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "PostgreSQL replica lag {{ $value | humanize1024 }}B > 10MB (~10s)"

      - alert: PostgreSQLStandbyMissing
        expr: absent(pg_stat_replication_pg_wal_lsn_diff{application_name="walreceiver"})
        for: 2m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "node6 standby replikasyona bağlı değil — HA koruması yok."
```

```bash
# node9'da Prometheus'u reload et:
curl -s -X POST http://127.0.0.1:9090/-/reload
```

### 10.3 Grafana

```bash
# Grafana apt reposu — promtail ve loki da bu repo üzerinden kurulur (bkz. §7.3):
apt-get install -y apt-transport-https software-properties-common
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor \
  | tee /usr/share/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana
# Sadece WireGuard üzerinden erişilir:
sed -i 's/;http_addr =/http_addr = 10.10.0.13/' /etc/grafana/grafana.ini
systemctl enable --now grafana-server
```

Panel: CPU, RAM, disk (node7/node8 disk%), Redis replication, LiveKit bağlantı sayısı.

**Grafana Data Sources (UI üzerinden):**
- Prometheus: `http://127.0.0.1:9090`
- Loki: `http://127.0.0.1:3100`

### 10.4 Loki + Promtail (node9)

#### Loki — node9'da kurulum

```bash
# Grafana reposu Faz 10.2'de eklendi; buradan devam:
apt-get install -y loki
mkdir -p /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
chown -R loki:loki /var/lib/loki
```

**`/etc/loki/config.yml`:**
```yaml
auth_enabled: false

server:
  http_listen_address: 10.10.0.13   # WireGuard IP — sadece WG üzerinden erişilir
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h   # 7 gün

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 5m
  retention_enabled: true
  retention_delete_delay: 2h
```

```bash
systemctl enable --now loki
# Doğrula:
curl -s http://10.10.0.13:3100/ready  # → "ready"
```

#### Promtail — node9 dahil tüm node'larda

Tüm node'larda kurulum Faz 7.3'te belgelenmiştir. node9 için ek adım yok — Faz 7.3'teki adımları node9'da da uygula (`<NODE_ID>=node9`).

```bash
# node9'da doğrula:
journalctl -u promtail -n 20
# Loki'ye log geldi mi?
curl -s "http://10.10.0.13:3100/loki/api/v1/query?query=%7Bnode%3D%22node9%22%7D" | python3 -m json.tool
```

### 10.5 Alertmanager → Telegram

**Alert kanal mimarisi:**
| Alert | Kaynak | Kanal |
|-------|--------|-------|
| Node down, gateway down, storage down | Prometheus → Alertmanager | `#alerts` |
| node5 CPU > 85%, disk > 85% | Prometheus → Alertmanager | `#ops` |
| Keepalived VIP geçişi | `wg_vip_failover.sh` → doğrudan Telegram API | `#alerts` |
| Dual-write phase değişimi | Orchestrator backend → doğrudan Telegram API | `#ops` |
| PostgreSQL replica lag / standby kayıp | Prometheus → Alertmanager (postgres_exporter, bkz. §10.1) | `#alerts` |

#### Alertmanager kurulumu (node9)

```bash
apt-get install -y prometheus-alertmanager
```

**`/etc/alertmanager/alertmanager.yml`:**
```yaml
global:
  resolve_timeout: 5m

route:
  group_by: [alertname, instance]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: ops
  routes:
    - match:
        severity: critical
      receiver: alerts
      repeat_interval: 1h

receivers:
  - name: ops
    telegram_configs:
      - bot_token: '<TELEGRAM_BOT_TOKEN>'
        chat_id: <TELEGRAM_CHAT_ID_OPS>       # #ops kanalı chat ID
        parse_mode: Markdown
        message: |-
          *{{ .GroupLabels.alertname }}*
          {{ range .Alerts }}{{ .Annotations.description }}
          {{ end }}

  - name: alerts
    telegram_configs:
      - bot_token: '<TELEGRAM_BOT_TOKEN>'
        chat_id: <TELEGRAM_CHAT_ID_ALERTS>    # #alerts kanalı chat ID
        parse_mode: Markdown
        message: |-
          🚨 *CRITICAL: {{ .GroupLabels.alertname }}*
          {{ range .Alerts }}{{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_matchers:
      - alertname = NodeDown
    target_matchers:
      - severity = warning
    equal:
      - instance
```

```bash
systemctl enable --now prometheus-alertmanager
# Prometheus reload (alert_rules.yml eklendi, bkz. §10.1):
curl -s -X POST http://127.0.0.1:9090/-/reload
# Doğrula:
curl -s http://127.0.0.1:9093/#/alerts  # → Alertmanager UI (WG üzerinden)
```

**Keepalived VIP geçişi bildirimi** — `wg_vip_failover.sh` MASTER bloğu adım 8'de tanımlanmıştır (§4.5). `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID_ALERTS` `/etc/keepalived/secrets/failover.env`'den okunur — ayrıca ekleme gerekmez.

### 10.6 Yedekleme (node9)

**node9 disk:** 3.5 TB HDD RAID-1 — monitoring + backup + ClickHouse için yeterli alan. `/data` partition'ı tüm servislerin verisini taşır.

**RPO:** pg_receivewal ile dakika seviyesinde (PITR). pg_dump günlük mantıksal backup.

**Kapsam:**

| Veri | Yöntem | RPO | Öncelik |
|------|--------|-----|---------|
| PostgreSQL | pg_receivewal (sürekli) + pg_basebackup (haftalık) + pg_dump (günlük) | Dakika | Kritik |
| MinIO nesneleri | Dual-Write (node7+8) + cold archive node9 (günlük `mc mirror`) + off-site B2 (günlük rclone) | 24 saat | Yüksek |
| Redis Core | RDB günlük rsync (node5→node9) | 24 saat | Orta |
| ClickHouse | Günlük BACKUP komutu + off-site | 24 saat | Orta |
| WireGuard private key | Manuel → password manager | Tek seferlik | Kritik |

#### 10.6.1 Kurulum (node9)

```bash
# PGDG repo (node9'da postgresql-client-17 için — Faz 4.1'deki aynı adımlar):
apt-get install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh

# PostgreSQL client (pg_receivewal, pg_basebackup, pg_dump):
apt-get install -y postgresql-client-17

# rclone (off-site sync):
curl -fsSL https://rclone.org/install.sh | bash

# Dizin yapısı:
mkdir -p /data/teqlif_backups/{postgres/{wal,basebackup,dump},redis,offsite-log}
mkdir -p /opt/teqlif/scripts
[ -L /opt/teqlif/backups ] || ln -s /data/teqlif_backups /opt/teqlif/backups
chown -R tucibeyin:tucibeyin /data/teqlif_backups /opt/teqlif/scripts
chmod 700 /data/teqlif_backups
chmod 750 /opt/teqlif/scripts
```

**Backup log rotasyonu (node9) — Faz 1.10 logrotate kuralı yalnızca alt dizin log'larını kapsar; backup scriptleri doğrudan `/var/log/teqlif/*.log`'a yazar:**
```bash
cat >> /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/pg_basebackup.log
/var/log/teqlif/pg_dump.log
/var/log/teqlif/redis_backup.log
/var/log/teqlif/clickhouse_backup.log
/var/log/teqlif/offsite_sync.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

**SSH kurulumu — node9→node5 rsync için (redis ve ClickHouse backup):**
```bash
# node9'da:
su - tucibeyin -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' 2>/dev/null || true"
# node9'un public key'ini node5'in authorized_keys'ine ekle (Faz 2 mesh'te yapılabilir):
cat /home/tucibeyin/.ssh/id_ed25519.pub
# → Bu çıktıyı node5'te: echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
# Test:
ssh -o BatchMode=yes -o StrictHostKeyChecking=no tucibeyin@10.10.0.5 hostname  # → node5 hostname
```

**node6 failover SSH key — §4.5'teki node6 authorized_keys adımı node9 kurulumunda tamamlanır:**
```bash
# node6'dan alınan ~/.ssh/id_ed25519_failover.pub değeri node9'a da eklenmeli:
# node9'da:
echo "<node6_failover_pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
chmod 600 /home/tucibeyin/.ssh/authorized_keys
```

**node6 pg_hba.conf — node9 backup bağlantısı için:**
```bash
# pg_basebackup WAL replication üzerinden pg_hba.conf değişikliklerini yansıtmaz.
# node5'teki §4.1 girişleri node6'ya manuel eklenmeli:
# node6'da:
echo "host  teqlif      teqlif      10.10.0.13/32    scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
echo "host  replication replicator  10.10.0.13/32    scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
psql -h 127.0.0.1 -U postgres -c "SELECT pg_reload_conf();"
# Doğrula:
psql -h 127.0.0.1 -U postgres -c "SELECT line_number, rule_type, address FROM pg_hba_file_rules WHERE address = '10.10.0.13/32';"
```

#### 10.6.2 pg_receivewal — Sürekli WAL Arşivleme

pg_receivewal, node9'dan node5'e streaming protokolüyle bağlanır ve WAL segmentlerini gerçek zamanlı çeker. `archive_command` gerektirmez, SSH key gerektirmez.

```bash
# Replikasyon slotu oluştur (node5'te — slot WAL'ın silinmesini engeller):
psql -h 10.10.0.5 -p 5432 -U replicator -c \
  "SELECT pg_create_physical_replication_slot('wal_backup_node9');"
```

**`/etc/systemd/system/teqlif-pg-receivewal.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-pg-receivewal.service \
   /etc/systemd/system/teqlif-pg-receivewal.service
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif-pg-receivewal
# Doğrula:
journalctl -u teqlif-pg-receivewal -n 20
ls /opt/teqlif/backups/postgres/wal/   # → .gz.partial dosyası birikmeye başlar
```

**WAL temizleme (7 günden eski segmentler):**
```bash
cat >> /etc/cron.daily/teqlif-wal-cleanup << 'EOF'
#!/bin/bash
find /opt/teqlif/backups/postgres/wal/ -name "*.gz" -mtime +7 -delete
EOF
chmod +x /etc/cron.daily/teqlif-wal-cleanup
```

> **Failover sonrası WAL gap:** Failover sırasında failover script node6'da yeni `wal_backup_node9` slotu oluşturur; slotun `restart_lsn`'i o andaki node6 LSN'idir. pg_receivewal'ın node5'ten aldığı son WAL ile bu LSN arasındaki segment eksik kalır — PITR arşivinde gap oluşur. Kabul edilebilir bir sınırlıktır ancak **failover sonrasında §10.6.3'ten bir `pg_basebackup` çalıştırarak yeni bir PITR baseline oluşturulmalıdır.** Bu yapılmadan gap öncesine PITR yapılamaz.

#### 10.6.3 pg_basebackup — Haftalık Fiziksel Yedek

Fiziksel backup, PITR'ın başlangıç noktasıdır. pg_receivewal'ın WAL segmentleriyle birlikte kullanılır.

**`/opt/teqlif/scripts/pg_basebackup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/postgres/basebackup"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/pg_basebackup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: start"

export PGPASSWORD="${REPLICATOR_PASSWORD}"   # .env.production'dan — service EnvironmentFile ile yüklenir

# Geçici dizine yaz; hata/kesintide current geçerli kalır — yarım backup promote edilmez
TEMP_DIR="${BACKUP_DIR}/.current_tmp"
rm -rf "${TEMP_DIR}"
cleanup_temp() { rm -rf "${TEMP_DIR}"; }
trap cleanup_temp EXIT

pg_basebackup \
  --host=10.10.0.10 \
  --port=5432 \
  --username=replicator \
  --pgdata="${TEMP_DIR}" \
  --format=tar \
  --gzip \
  --compress=9 \
  --wal-method=none \
  --progress \
  --verbose

# Başarılıysa atomik rename; önceki current'i previous olarak sakla
trap - EXIT
[ -d "${BACKUP_DIR}/current" ] && mv "${BACKUP_DIR}/current" "${BACKUP_DIR}/previous_${DATE}"
mv "${TEMP_DIR}" "${BACKUP_DIR}/current"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: OK — $(du -sh ${BACKUP_DIR}/current | cut -f1)"

# Bir haftalıktan eski previous_* dizinlerini sil:
find "${BACKUP_DIR}" -maxdepth 1 -name "previous_*" -mtime +7 -exec rm -rf {} +
```

```bash
chmod 750 /opt/teqlif/scripts/pg_basebackup.sh
```

**`/etc/systemd/system/teqlif-pg-basebackup.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-pg-basebackup.service \
   /etc/systemd/system/teqlif-pg-basebackup.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-pg-basebackup.timer \
   /etc/systemd/system/teqlif-pg-basebackup.timer
```

```bash
systemctl enable --now teqlif-pg-basebackup.timer
```

#### 10.6.4 pg_dump — Günlük Mantıksal Yedek

Bireysel tablo geri yüklemesi için kullanılır. pg_basebackup'tan bağımsız.

**`/opt/teqlif/scripts/pg_dump.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/postgres/dump"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/pg_dump.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_dump: start"

export PGPASSWORD="${PG_PASSWORD}"   # .env.production'dan — service EnvironmentFile ile yüklenir

# Geçici dosyaya yaz; tamamlanmadan final ismine geçme — kesintide yarım dosya kalmaz
TMPFILE="${BACKUP_DIR}/teqlif_${DATE}.sql.gz.tmp"
cleanup_tmp() { rm -f "${TMPFILE}"; }
trap cleanup_tmp EXIT

pg_dump -h 10.10.0.10 -p 5432 -U teqlif teqlif \
  | gzip -9 > "${TMPFILE}"

trap - EXIT
mv "${TMPFILE}" "${BACKUP_DIR}/teqlif_${DATE}.sql.gz"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_dump: OK — $(du -sh ${BACKUP_DIR}/teqlif_${DATE}.sql.gz | cut -f1)"
find "${BACKUP_DIR}" -name "teqlif_*.sql.gz" -mtime +7 -delete
```

```bash
chmod 750 /opt/teqlif/scripts/pg_dump.sh
```

**`/etc/systemd/system/teqlif-pg-dump.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-pg-dump.service \
   /etc/systemd/system/teqlif-pg-dump.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-pg-dump.timer \
   /etc/systemd/system/teqlif-pg-dump.timer
```

```bash
systemctl enable --now teqlif-pg-dump.timer
```

#### 10.6.5 PITR Kurtarma Prosedürü

```bash
# Hedef: 2026-10-20 14:35:00 UTC tarihine geri dön

# 1. Yeni node'da (veya node5 sıfırlandıktan sonra) basebackup'ı aç:
mkdir -p /var/lib/postgresql/17/main
cd /var/lib/postgresql/17/main
tar -xzf /opt/teqlif/backups/postgres/basebackup/current/base.tar.gz
# (tablespace tar dosyaları da varsa aç)

# 2. PITR recovery config:
cat > /var/lib/postgresql/17/main/postgresql.conf << 'EOF'
restore_command = 'gunzip -c /opt/teqlif/backups/postgres/wal/%f.gz > %p'
recovery_target_time = '2026-10-20 14:35:00+00'
recovery_target_action = 'promote'
EOF
touch /var/lib/postgresql/17/main/recovery.signal

# 3. PostgreSQL'i başlat — WAL replay eder, hedef zamana gelince promote eder:
chown -R postgres:postgres /var/lib/postgresql/17/main
systemctl start postgresql
journalctl -u postgresql -f   # "recovery stopping before commit" → promote tamamlandı
```

#### 10.6.6 Redis RDB Yedekleme

Core Redis RDB dosyasını günlük node9'a çeker. Session kaybında kullanıcılar yeniden giriş yapar — düşük öncelikli ama temiz kurulumda yapmak kolay.

`redis-cli --rdb` komutu kullanılır: Redis protokolü üzerinden RDB'yi doğrudan hedef dosyaya yazar. BGSAVE+rsync yaklaşımı kullanılmaz çünkü `/var/lib/redis-core/dump.rdb` dosyası `redis:redis 640`'tır ve tucibeyin dosya sisteminden okuyamaz.

**`/opt/teqlif/scripts/redis_backup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/redis"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/redis_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis_backup: start"

# redis-cli --rdb: Redis replikasyon protokolüyle RDB snapshot'ı doğrudan alır.
# Dosya sistemi erişimi gerekmez — /var/lib/redis-core/ izni sorun değil.
# VIP (10.10.0.11) üzerinden bağlanır; failover sonrası node6'da da çalışır.
TMPFILE="${BACKUP_DIR}/core_redis_${DATE}.rdb.tmp"
cleanup_tmp() { rm -f "${TMPFILE}"; }
trap cleanup_tmp EXIT

redis-cli -h 10.10.0.11 -p 6379 -a "${CORE_REDIS_PASS}" \
  --rdb "${TMPFILE}"

trap - EXIT
mv "${TMPFILE}" "${BACKUP_DIR}/core_redis_${DATE}.rdb"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis_backup: OK — $(du -sh ${BACKUP_DIR}/core_redis_${DATE}.rdb | cut -f1)"
find "${BACKUP_DIR}" -name "core_redis_*.rdb" -mtime +7 -delete
```

```bash
chmod 750 /opt/teqlif/scripts/redis_backup.sh
```

**`/etc/systemd/system/teqlif-redis-backup.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-redis-backup.service \
   /etc/systemd/system/teqlif-redis-backup.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-redis-backup.timer \
   /etc/systemd/system/teqlif-redis-backup.timer
```

```bash
systemctl enable --now teqlif-redis-backup.timer
```

#### 10.6.7 ClickHouse Yedekleme

**`/opt/teqlif/scripts/clickhouse_backup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/data/clickhouse/backups"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/clickhouse_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: start"

# node9: ClickHouse lokal — 127.0.0.1
CH_HOST="127.0.0.1"
CH_PORT="8123"
CH_USER="${CLICKHOUSE_USER}"
CH_PASS="${CLICKHOUSE_PASSWORD}"

# Başarısız/yarım backup'ı temizle — lokal disk şişmesini önle
cleanup_local() {
  rm -rf "${BACKUP_DIR}/ch_backup_${DATE}" 2>/dev/null || true
}
trap cleanup_local EXIT

# ClickHouse BACKUP komutu — lokal /data/clickhouse/backups/ altına yazar
curl -sf "http://${CH_HOST}:${CH_PORT}/?user=${CH_USER}&password=${CH_PASS}&query=BACKUP+DATABASE+teqlif+TO+Disk('backups','ch_backup_${DATE}')" > /dev/null

# Tamamlanana kadar bekle (max 120s):
STATUS="UNKNOWN"
for i in $(seq 1 24); do
  STATUS=$(curl -sf "http://${CH_HOST}:${CH_PORT}/?user=${CH_USER}&password=${CH_PASS}&query=SELECT+status+FROM+system.backups+WHERE+name%3D'ch_backup_${DATE}'+LIMIT+1" || echo "QUERY_ERROR")
  [ "${STATUS}" = "BACKUP_CREATED" ] && break
  sleep 5
done

if [ "${STATUS}" != "BACKUP_CREATED" ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: HATA — backup tamamlanmadı (status=${STATUS})"
  exit 1   # trap cleanup_local çalışır
fi

trap - EXIT
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK — $(du -sh ${BACKUP_DIR}/ch_backup_${DATE} | cut -f1)"
find "${BACKUP_DIR}" -maxdepth 1 -name "ch_backup_*" -mtime +2 -exec rm -rf {} +
```

```bash
chmod 750 /opt/teqlif/scripts/clickhouse_backup.sh
```

**`/etc/systemd/system/teqlif-clickhouse-backup.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-clickhouse-backup.service \
   /etc/systemd/system/teqlif-clickhouse-backup.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-clickhouse-backup.timer \
   /etc/systemd/system/teqlif-clickhouse-backup.timer
```

```bash
systemctl enable --now teqlif-clickhouse-backup.timer
```

#### 10.6.8 MinIO Cold Archive (node9)

node7 ve node8 MinIO verilerini `mc mirror` ile node9'a çeker. Her iki bucket — `teqlif` (genel medya) ve `teqlif-dm` (DM medyası) — ayrı ayrı arşivlenir. `mc` HTTP ile MinIO API'ye bağlanır; SSH veya dosya sistemi erişimi gerekmez.

**mc kurulumu (node9'da — Faz 10.6.1 sonrası):**
```bash
MC_VER="RELEASE.2024-11-17T19-35-25Z"
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VER}" \
  -o /usr/local/bin/mc
chmod 755 /usr/local/bin/mc

# MinIO alias — node7 (primary), node8 (fallback)
# Kimlik bilgileri .env.production'dan gelir
mc alias set node7minio "http://10.10.0.8:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
mc alias set node8minio "http://10.10.0.12:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
```

**`/opt/teqlif/scripts/minio_backup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_BASE="/data/backups/minio"
LOGFILE="/var/log/teqlif/minio_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: start"

# .env.production'dan kimlik bilgilerini yükle
source /etc/teqlif/.env.production

# mc alias'larını bu oturumda tanımla (script root olarak çalışmayabilir)
mc alias set node7minio "http://10.10.0.8:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet
mc alias set node8minio "http://10.10.0.12:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

mirror_bucket() {
  local alias="$1" bucket="$2"
  local dest="${BACKUP_BASE}/${bucket}"
  mkdir -p "${dest}"
  mc mirror --overwrite --remove --quiet "${alias}/${bucket}" "${dest}" \
    && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} OK — $(du -sh ${dest} | cut -f1)"
}

# node7 primary — her iki bucket
if mc admin info node7minio --quiet &>/dev/null; then
  mirror_bucket node7minio teqlif
  mirror_bucket node7minio teqlif-dm
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: node7 erişilemiyor, node8 fallback"
  mirror_bucket node8minio teqlif
  mirror_bucket node8minio teqlif-dm
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: tamamlandı"
```

```bash
chmod 750 /opt/teqlif/scripts/minio_backup.sh
```

**`/etc/systemd/system/teqlif-minio-backup.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-minio-backup.service \
   /etc/systemd/system/teqlif-minio-backup.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-minio-backup.timer \
   /etc/systemd/system/teqlif-minio-backup.timer
```

```bash
systemctl enable --now teqlif-minio-backup.timer
```

#### 10.6.9 Off-site Yedekleme (rclone)

**rclone remote kurulumu (node3'te — sağlayıcı seçimi serbesttir):**

```bash
# Örnek: Backblaze B2 (S3-compatible, $0.006/GB/ay):
rclone config create b2backup b2 \
  account "<B2_ACCOUNT_ID>" \
  key "<B2_APPLICATION_KEY>"

# Alternatif: Hetzner Storage Box (rsync/SFTP, 100GB = €3.81/ay):
rclone config create hetzner sftp \
  host "<STORAGE_BOX_HOST>.your-storagebox.de" \
  user "<STORAGE_BOX_USER>" \
  pass "<STORAGE_BOX_PASS>"
```

**`/opt/teqlif/scripts/offsite_sync.sh`:**
```bash
#!/bin/bash
set -euo pipefail
REMOTE="b2backup:teqlif-backup"   # Backblaze B2 bucket adı
LOGFILE="/var/log/teqlif/offsite_sync.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: start"

# PostgreSQL dump'ları (günlük — 7 gün; lokal temizleme pg_dump.sh RETENTION_DAYS=7 yönetir)
rclone sync /data/backups/pg_dump/ "${REMOTE}/postgres/dump/" \
  --log-level INFO

# pg_basebackup (haftalık — lokal temizleme pg_basebackup.sh RETENTION_DAYS=7 yönetir)
rclone sync /data/backups/pg_basebackup/ "${REMOTE}/postgres/basebackup/" \
  --log-level INFO

# WAL segmentleri — pg_receivewal /opt/teqlif/backups/postgres/wal/ altına yazar
rclone sync /opt/teqlif/backups/postgres/wal/ "${REMOTE}/postgres/wal/" \
  --log-level INFO

# Redis RDB (günlük — 7 gün; lokal temizleme redis_backup.sh RETENTION_DAYS=7 yönetir)
rclone sync /data/backups/redis/ "${REMOTE}/redis/" \
  --log-level INFO

# ClickHouse (günlük — 7 gün; lokal temizleme clickhouse_backup.sh RETENTION_DAYS=7 yönetir)
rclone sync /data/clickhouse-backups/ "${REMOTE}/clickhouse/" \
  --transfers 2 --checkers 4 --log-level INFO

# MinIO cold archive (node9 lokal mirror — §10.6.8'de teqlif + teqlif-dm node7'den çekilir)
rclone sync /data/backups/minio/ "${REMOTE}/minio/" \
  --transfers 4 --checkers 8 --log-level INFO

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: OK"
```

```bash
chmod 750 /opt/teqlif/scripts/offsite_sync.sh
```

**`/etc/systemd/system/teqlif-offsite-sync.service`** + **`.timer`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-offsite-sync.service \
   /etc/systemd/system/teqlif-offsite-sync.service
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/systemd/teqlif-offsite-sync.timer \
   /etc/systemd/system/teqlif-offsite-sync.timer
```

```bash
systemctl enable --now teqlif-offsite-sync.timer
```

> **MinIO off-site:** `mc mirror` → node9 lokal (§10.6.8) → `offsite_sync.sh` → B2 akışıyla yapılır. node5'te ayrı cron gerekmez.

#### 10.6.10 Zamanlayıcı Özeti (node9)

| Saat (UTC) | Timer | İş |
|-----------|-------|-----|
| Sürekli | MinIO Site Replication | node7↔node8 anlık çift yönlü replikasyon (timer değil, MinIO yerleşik, bkz. Faz 6.9) |
| Sürekli | teqlif-pg-receivewal | Sürekli WAL stream (servis, zamanlayıcı değil) |
| 02:00 | teqlif-minio-backup | MinIO cold archive: teqlif + teqlif-dm → node9 lokal (`mc mirror` from node7) |
| 03:00 | teqlif-pg-dump | PostgreSQL mantıksal yedek |
| 03:30 | teqlif-redis-backup | Redis RDB rsync |
| 04:00 | teqlif-clickhouse-backup | ClickHouse günlük backup |
| 04:30 | teqlif-offsite-sync | PG + Redis + ClickHouse + MinIO → B2 off-site |
| Pazar 01:00 | teqlif-pg-basebackup | Haftalık fiziksel backup |

#### 10.6.11 WireGuard Private Key Kurtarma (Manuel — Tek Seferlik)

Her node kurulduktan **hemen sonra**:
```bash
# Her node'da:
wg showconf wg0 | grep PrivateKey
# → PrivateKey = <base64_key>
# Bu değeri password manager'a kaydet: "WireGuard PrivateKey — <node_adı>"
```

Kurtarma (node tamamen bozulursa):
```bash
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key
# 9 node'da o node'a ait peer kaydını yeni public key ile güncelle (Faz 2 wg set adımları)
```

#### 10.6.12 Disaster Recovery Tablosu

| Senaryo | RTO | Prosedür |
|---------|-----|---------|
| node5 geçici down | ~30s | Keepalived otomatik → node6 primary |
| node5 kalıcı arıza | ~2 saat | node6 permanent primary; yeni standby kur |
| node5 + node6 eş zamanlı | ~2 saat | pg_basebackup + WAL replay ile yeni node |
| Tablo/satır silme (DB) | < 5 dakika | PITR: `recovery_target_time` ile dakika hassasiyetli geri dön |
| node7 veya node8 geçici | 0 | nginx fallback → diğer node; nightly sync |
| MinIO nesne yanlış silindi | < 5 dakika | `mc cp --version-id <id>` ile geri yükle |
| Tüm node3 arızası | — | pg_dump + WAL off-site'ta; yeni node'a rclone'dan indir |
| node2 (AI Proxy) tamamen down | ~6s | Orchestrator `edge:metrics:node2` TTL → node3'e otomatik geçiş (`ai_proxy:active_url` güncellenir); kullanıcı bunu fark etmez |
| node2 + node3 (AI Proxy) eş zamanlı down | ~6s | Orchestrator node5'te `teqlif-ai-proxy` başlatır (disabled→enabled), `ai_proxy:active_url=http://10.10.0.5:8001`; node5 MemoryMax=600M kısıtlıdır |
| node1 + node4 eş zamanlı | dakikalar (OS) / manuel (OS arızası) | LiveKit tamamen kesilir — bilinen SPOF; `Restart=always` process crash'i kapatır |
| node7 + node8 eş zamanlı | — | Storage tamamen kesilir — bilinen SPOF; `Restart=always` process crash'i kapatır |
| Deluxhost DC kesintisi (node7+node8) | Kesinti süresi | **Kabul Edilen Risk:** Upload (PUT) durur; okuma Cloudflare edge cache'inden devam eder (CF: 1 ay, nginx: 7 gün). Yeni medya yüklenemez, mevcut içerik erişilebilir. DC geri gelince çift-yazma otomatik devam eder. |
| gateway1 + gateway2 eş zamanlı | — | Tam erişilemezlik — bilinen SPOF; pratik olasılık çok düşük (farklı DC) |
| Servis crash-loop (StartLimitBurst aşıldı) | manuel | Prometheus ServiceFailed alert → `systemctl reset-failed <servis> && systemctl start <servis>` |

### 10.7 Faz 10 Doğrulama

```bash
# Prometheus:
curl -s http://10.10.0.13:9090/api/v1/targets | python3 -c \
  "import sys,json; targets=json.load(sys.stdin)['data']['activeTargets']; \
   [print(t['labels']['instance'], t['health']) for t in targets]"
# → 11 target (node9 dahil), hepsi "up"

# Loki:
curl -s http://10.10.0.13:3100/ready   # → ready

# Alertmanager:
curl -s http://127.0.0.1:9093/-/healthy  # → OK

# pg_receivewal:
systemctl is-active teqlif-pg-receivewal   # → active
ls /opt/teqlif/backups/postgres/wal/       # → .gz.partial dosyası birikmeye başlamış

# Tüm backup timer'ları:
systemctl list-timers "teqlif-pg-*" "teqlif-redis-*" "teqlif-clickhouse-*" "teqlif-offsite-*"
# → hepsi active/waiting

# Manuel pg_dump testi:
systemctl start teqlif-pg-dump.service
ls -lh /opt/teqlif/backups/postgres/dump/   # → dump dosyası

# Off-site bağlantısı:
rclone lsd b2backup:                         # → bucket listesi görünmeli

# MinIO versioning (node5'ten çalıştır — mc orada kurulu, Faz 6.9):
# ssh node5, sonra:
# mc version info minio7/teqlif   # → Versioning: enabled
# mc version info minio8/teqlif   # → Versioning: enabled
```

---

## Faz 11 — Staging (node3)

**Önkoşul:** Faz 10 tamamlandı.

**Tasarım:** node3 tam izole staging node'u — tüm bağımlılıklar lokal. PostgreSQL, Redis, MinIO, LiveKit dahil tüm servisler node3 üzerinde çalışır; prod node5/6/7/8'e bağımlılık yok. ClickHouse analytics devre dışı (3.8GB RAM, non-critical). HTTPS trafiği yine de gateway üzerinden akar; iç stack lokal.

### 11.1 PostgreSQL — node3 lokal

```bash
# PGDG repo Faz 10.1'de zaten eklendi
apt-get install -y postgresql-17
systemctl enable --now postgresql

# Sadece lokal bağlantılar
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '127.0.0.1'/" \
  /etc/postgresql/17/main/postgresql.conf
systemctl restart postgresql

# Staging DB + user
sudo -u postgres psql <<'SQL'
CREATE USER teqlif WITH ENCRYPTED PASSWORD '<staging_pg_pass>';
CREATE DATABASE teqlif_staging OWNER teqlif;
SQL

psql -h 127.0.0.1 -U teqlif -d teqlif_staging -c '\conninfo'  # → bağlantı doğrula
```

### 11.2 Redis — node3 lokal

```bash
apt-get install -y redis-server

cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/redis/redis-staging.conf \
   /etc/redis/redis-staging.conf
# <staging_redis_pass> placeholder'ını doldur
sed -i "s/<staging_redis_pass>/${STAGING_REDIS_PASS}/" /etc/redis/redis-staging.conf

cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/redis-staging.service \
   /etc/systemd/system/redis-staging.service

systemctl daemon-reload
systemctl enable --now redis-staging
redis-cli -h 127.0.0.1 -p 6379 -a <staging_redis_pass> ping  # → PONG
```

### 11.3 MinIO — node3 lokal (staging)

node3'ün kendi MinIO instance'ı: `teqlif-staging` ve `teqlif-dm-staging` bucket'ları lokal. Prod node7/node8'e bağımlılık yok.

```bash
MINIO_RELEASE="RELEASE.2024-11-07T00-52-20Z"
curl -fsSL "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/minio.linux-amd64.${MINIO_RELEASE}" \
  -o /usr/local/bin/minio
chmod 755 /usr/local/bin/minio

mkdir -p /var/lib/minio-staging /var/log/teqlif/minio
chown tucibeyin:tucibeyin /var/lib/minio-staging /var/log/teqlif/minio

cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/minio-staging.service \
   /etc/systemd/system/minio-staging.service
systemctl daemon-reload
systemctl enable --now minio-staging
```

**Staging bucket'larını oluştur** (mc, binary node9'da olduğu gibi indir):
```bash
MC_RELEASE="RELEASE.2024-11-07T00-52-20Z"
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_RELEASE}" \
  -o /usr/local/bin/mc && chmod 755 /usr/local/bin/mc

source /etc/teqlif/.env.staging
mc alias set local "http://127.0.0.1:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
mc mb local/teqlif-staging
mc mb local/teqlif-dm-staging
mc anonymous set download local/teqlif-staging   # public okuma (media)
# teqlif-dm-staging private kalır — presigned GET ile erişilir
```

**`/etc/nginx/sites-available/staging`** güncellemesi (media-staging + uploads-staging vhost eklendi):
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/nginx/sites-available/staging \
   /etc/nginx/sites-available/staging
nginx -t && systemctl reload nginx
```

> **DNS (Cloudflare):** `media-staging.teqlif.com` → node3 public IP (Proxied); `uploads-staging.teqlif.com` → node3 public IP (**DNS Only** — presigned PUT imzası CF proxy'den geçemez).

### 11.4 LiveKit — node3 lokal (staging)

node3'ün kendi LiveKit instance'ı: prod node1/node4'e bağımlılık yok.

```bash
LIVEKIT_VER="v1.7.2"
curl -fsSL "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin livekit-server

mkdir -p /etc/livekit
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/livekit/livekit.yaml \
   /etc/livekit/livekit-staging.yaml
# <placeholder> değerlerini doldur: staging_redis_pass, livekit_staging_api_key/secret

cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/livekit-staging.service \
   /etc/systemd/system/livekit-staging.service
systemctl daemon-reload
systemctl enable --now livekit-staging
```

**UFW — LiveKit portları:**
```bash
ufw allow 7880/tcp   # LiveKit API (iç mesh — sadece WireGuard üzerinden erişilir)
ufw allow 7881/tcp   # RTC TCP
ufw allow 7882/udp   # RTC UDP
ufw allow 3478/udp   # TURN UDP
ufw allow 5349/tcp   # TURN TLS
```

> **DNS (Cloudflare):** `live-staging.teqlif.com` → node3 public IP (**DNS Only** — TURN TLS direkt bağlantı gerektirir).

### 11.5 Staging App

node3 ayrı bir sunucu (ZAP VA) — kendi monorepo'su ve venv'i gerekir.

```bash
git clone git@github.com:tucibeyin/teqlif.git /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r backend/requirements.txt
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/.env.staging.template \
   /etc/teqlif/.env.staging
chmod 600 /etc/teqlif/.env.staging
chown tucibeyin:tucibeyin /etc/teqlif/.env.staging
# <placeholder> değerlerini ~/teqlif-secrets.env'den doldur (§0.0)
```

**`.env.staging` içeriği için bkz. §0.5 node3 template'i** — tüm key'ler orada tanımlı. `SITE_URL=https://staging.teqlif.com`, `WEB_APP_ENABLED=True`, `APNS_USE_SANDBOX=True` gibi staging'e özgü değerler template'e zaten işlenmiş durumda.

**teqlif-guardian systemd drop-in — node3'e özgü** (`teqlif-guardian.service` varsayılan olarak `/etc/teqlif/.env.production` okur; node3'te bu dosya yoktur):

```bash
mkdir -p /etc/systemd/system/teqlif-guardian.service.d
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-guardian.service.d/staging-env.conf \
   /etc/systemd/system/teqlif-guardian.service.d/staging-env.conf
systemctl daemon-reload
```

**Staging DB şeması:**
```bash
cd /var/www/teqlif.com/backend
source ../.venv/bin/activate
DATABASE_URL="postgresql+asyncpg://teqlif:<staging_pg_pass>@127.0.0.1:5432/teqlif_staging" \
  alembic upgrade head
```

**`/etc/systemd/system/teqlif-staging.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-staging.service \
   /etc/systemd/system/teqlif-staging.service
```

**`/etc/systemd/system/teqlif-worker-staging.service`:**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-worker-staging.service \
   /etc/systemd/system/teqlif-worker-staging.service
```

**`/etc/systemd/system/teqlif-worker-critical-staging.service`** (push bildirimleri, outbid, loser cascade):
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-worker-critical-staging.service \
   /etc/systemd/system/teqlif-worker-critical-staging.service
```

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/systemd/teqlif-guardian.service \
   /etc/systemd/system/teqlif-guardian.service
# node3'e özgü drop-in: guardian .env.production yerine .env.staging okusun
mkdir -p /etc/systemd/system/teqlif-guardian.service.d
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-guardian.service.d/staging-env.conf \
   /etc/systemd/system/teqlif-guardian.service.d/staging-env.conf
systemctl daemon-reload
systemctl enable --now teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging teqlif-guardian
```

**AI Proxy (node3'te her zaman çalışır — staging'de trafik 127.0.0.1:8001'e gider):**
```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/systemd/teqlif-ai-proxy.service \
   /etc/systemd/system/teqlif-ai-proxy.service
systemctl daemon-reload
systemctl enable --now teqlif-ai-proxy
```

**Gizli dosyalar — node3'e kopyala** (SFTP veya güvenli kanaldan):
```bash
# Firebase service account (FCM push bildirimleri — prod ve staging aynı proje)
cp ~/firebase-service-account.json /etc/teqlif/firebase-service-account.json
chmod 600 /etc/teqlif/firebase-service-account.json
chown tucibeyin:tucibeyin /etc/teqlif/firebase-service-account.json

# APNS VoIP key (iOS push — APNS_USE_SANDBOX=True staging'de sandbox APNs'ye gider)
cp ~/AuthKey_<apns_key_id>.p8 /etc/teqlif/AuthKey_<apns_key_id>.p8
chmod 600 /etc/teqlif/AuthKey_<apns_key_id>.p8
chown tucibeyin:tucibeyin /etc/teqlif/AuthKey_<apns_key_id>.p8
```

> **Not:** `firebase-service-account.json` ve `AuthKey_*.p8` repoya GİRMEZ — gizlilik sınırı. Lokal kasadan SFTP ile kopyalanır.

### 11.6 Nginx (staging erişimi — node3)

```bash
apt-get install -y nginx

mkdir -p /etc/ssl/teqlif
chmod 700 /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir → kopyala:
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

**Nginx config** (`node3/resources/nginx/sites-available/staging` — 3 vhost: staging API, media-staging okuma, uploads-staging yazma):

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/nginx/sites-available/staging \
   /etc/nginx/sites-available/staging
ln -s /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/
nginx -t && systemctl enable --now nginx
```

> **Not:** nginx config §11.3 (MinIO) adımında da güncellenir — `cp ... && systemctl reload nginx`. §11.6 kurulum adımı; §11.3 güncelleme adımı.

**UFW — MinIO iç erişim:**
```bash
ufw deny 9000/tcp  # MinIO doğrudan erişim engelle — yalnızca nginx :443 üzerinden
```

### 11.7 Faz 11 Doğrulama

```bash
curl -s https://staging.teqlif.com/health  # → 200
psql -h 127.0.0.1 -U teqlif -d teqlif_staging -c '\dt'  # → alembic tabloları
redis-cli -h 127.0.0.1 -p 6379 -a <staging_redis_pass> ping  # → PONG
curl -s http://127.0.0.1:9000/minio/health/live  # → 200 (MinIO lokal)
curl -s http://127.0.0.1:7880  # → LiveKit API yanıt
curl -s http://127.0.0.1:8001/health  # → 200 (AI proxy lokal)
systemctl is-active teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging \
  redis-staging postgresql minio-staging livekit-staging teqlif-ai-proxy teqlif-guardian
# Gizli dosyalar var mı?
ls -la /etc/teqlif/firebase-service-account.json /etc/teqlif/AuthKey_*.p8
```

- [ ] `alembic upgrade head` (staging DB — lokal 127.0.0.1)
- [ ] Servisler: `teqlif-staging`, `teqlif-worker-staging`, `teqlif-worker-critical-staging`, `redis-staging`, `postgresql`, `minio-staging`, `livekit-staging`, `teqlif-ai-proxy`, `teqlif-guardian`
- [ ] `firebase-service-account.json` + `AuthKey_*.p8` `/etc/teqlif/` altında mevcut
- [ ] MinIO bucket'ları: `mc ls local/teqlif-staging` + `mc ls local/teqlif-dm-staging`
- [ ] Presigned upload test: `uploads-staging.teqlif.com` → PUT 200

**Cloudflare DNS:**
- [ ] `uploads-staging.teqlif.com` → node3 public IP (**DNS Only**)
- [ ] `media-staging.teqlif.com`   → node3 public IP (Proxied)
- [ ] `live-staging.teqlif.com`    → node3 public IP (**DNS Only**)
- [ ] `staging.teqlif.com`         → node3 public IP (Proxied, gateway üzerinden)

### 11.8 Entegrasyon Testleri

- [ ] Kullanıcı akışı: kayıt → ilan oluştur → medya yükle → teklif ver → mesajlaş
- [ ] DM medya: upload → `cache_key` alanı mevcut → mobile cache doğru çalışıyor
- [ ] WebSocket bağlantısı + KeepAlive döngüsü
- [ ] Push notification (Firebase test token)
- [ ] OTA çeviri güncelleme
- [ ] Storage dual-write routing simülasyonu
- [ ] Keepalived failover staging'de tekrar

---

## Faz 12 — Prodüksiyon + Mobile

**Önkoşul:** Faz 11 tamamlandı, tüm testler geçiyor.

### 12.1 Son Kontrol Listesi

- [ ] CF DNS: `teqlif.com` + `api.teqlif.com` → iki A record aktif (gateway1 + gateway2)
- [ ] CF DNS: `uploads.teqlif.com` + `media.teqlif.com` → iki A record (node7 + node8)
- [ ] node5: teqlif + teqlif-worker + teqlif-worker-critical + teqlif-guardian → active
- [ ] `orch:best:storage_nodes = ["node7","node8"]` doğrula
- [ ] node6: keepalived active; teqlif/worker disabled; teqlif-guardian active
- [ ] node7 + node8: minio + teqlif-guardian → active
- [ ] Monitoring: tüm node'lar Prometheus'ta görünüyor (`curl -s http://10.10.0.13:9090/api/v1/targets | python3 -m json.tool`)
- [ ] Loki: tüm node'lardan log akıyor (`curl -s "http://10.10.0.13:3100/loki/api/v1/labels"` — node label'ları görünmeli)
- [ ] Alertmanager: test alert gönder (`curl -s -X POST http://127.0.0.1:9093/api/v1/alerts -d '[{"labels":{"alertname":"Test"}}]'`)
- [ ] Presigned upload doğrula: `POST /api/upload/presign` → put_url `uploads.teqlif.com` içeriyor; `PUT` direkt node7/node8'e gidiyor (gateway log'unda media byte'ı görünmemeli)
- [ ] Tüm `UploadFile` endpoint'leri kaldırıldı — gateway log'unda Content-Length > 100KB olan POST yok
- [ ] Gateway nginx `client_max_body_size 5m` doğrula: `nginx -T | grep client_max_body_size` → 5m (V2.0 başlangıcından beri 5m, değişiklik gerekmez)
- [ ] Dual-write: bir medya yükle → her iki storage node'da mc ls ile doğrula
- [ ] MinIO versioning aktif: `mc version info minio7/teqlif` + `minio8/teqlif` → `Versioning: enabled`
- [ ] pg_receivewal aktif: `systemctl is-active teqlif-pg-receivewal` + WAL dosyaları birikmeye başladı
- [ ] İlk pg_dump başarılı: `ls -lh /opt/teqlif/backups/postgres/dump/` → dosya mevcut
- [ ] Off-site rclone bağlantısı: `rclone lsd b2backup:` → bucket görünüyor
- [ ] WireGuard private key'ler password manager'a kaydedildi (tüm 11 node)

### 12.2 Mobile Güncellemesi

- [ ] `dart_defines/release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` güncelle (bkz. Faz 0.10)
- [ ] `dart_defines/staging.json`: aynı anahtarlar staging değerleriyle
- [ ] `frontend/.well-known/assetlinks.json` — Android App Links (bkz. Faz 0.10)
- [ ] `frontend/.well-known/apple-app-site-association` — iOS Universal Links (bkz. Faz 0.10)
- [ ] Android: Play Store internal track
- [ ] iOS: App Store TestFlight

---

## Faz 13 — node9 Doğrulama + Tam Entegrasyon

**Önkoşul:** Faz 12 tamamlandı. Prodüksiyon trafiği canlı, Faz 10'da kurulan tüm node9 servisleri ayakta.

> Bu faz tamamen doğrulama + entegrasyon testidir. Yeni kurulum komutu yoktur — Faz 10'da kurulan servisler prod trafik altında test edilir.

### 13.1 WireGuard Mesh Bütünlüğü

```bash
# node9'dan tüm node'lara ping:
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 \
          10.10.0.6 10.10.0.7 10.10.0.8 10.10.0.9 10.10.0.12; do
  ping -c1 -W2 "${ip}" > /dev/null && echo "OK: ${ip}" || echo "FAIL: ${ip}"
done
# → Tümü OK

# Diğer node'lardan node9'a ping:
# node5'te:
ping -c1 10.10.0.13  # → OK
# gateway1'de:
ping -c1 10.10.0.13  # → OK

# WireGuard handshake zamanları güncel mi?
wg show wg0  # her peer'da Latest handshake: < 5 dakika
```

### 13.2 ClickHouse — Prod Veri Akışı Doğrulaması

```bash
# node9'da: prod başladıktan sonra ilk yazma geldi mi?
clickhouse-client --user=teqlif --password=<pass> \
  --query="SELECT count(), max(created_at) FROM teqlif.analytics_events LIMIT 1"
# → satır sayısı > 0, max(created_at) son dakikalarda

# node5'ten ClickHouse'a erişim:
curl -sf "http://10.10.0.13:8123/?user=teqlif&password=<pass>&query=SELECT+1"
# → 1

# Circuit breaker durumu (node9 geçici kapatma testi):
# node9'da:
systemctl stop clickhouse-server
# node5'te bir analytics endpoint'e istek gönder — uygulama çalışmaya devam etmeli
curl -s https://api.teqlif.com/v1/ping  # → 200 (analytics degraded, app UP)
# node9'da:
systemctl start clickhouse-server
```

### 13.3 Prometheus — Tüm Node'lar Scrape Ediliyor

```bash
# node9'dan:
curl -s 'http://127.0.0.1:9090/api/v1/targets' | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']['activeTargets']
up = [t for t in data if t['health'] == 'up']
down = [t for t in data if t['health'] != 'up']
print(f'UP: {len(up)}, DOWN: {len(down)}')
for t in down: print('  FAIL:', t['labels']['instance'])
"
# → UP: 11, DOWN: 0  (node9 kendisi dahil)

# node9 scrape ediliyor mu?
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up%7Binstance%3D%2210.10.0.13%3A9100%22%7D' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['data']['result'])"
# → [{'metric': ..., 'value': [..., '1']}]  → 1 = up
```

### 13.4 Loki — Tüm Node'lardan Log Akışı

```bash
# node9'dan Loki: labels sorgusu
curl -s 'http://127.0.0.1:3100/loki/api/v1/labels' | python3 -m json.tool
# → "node" label'ı var

# Tüm node'lar loglanıyor mu?
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range?query=%7Bjob%3D%22journal%22%7D&limit=1&start=1h' \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
nodes = set(s['stream'].get('node','?') for s in r['data']['result'])
print('Nodes logging:', sorted(nodes))
"
# → Nodes logging: ['gateway1', 'gateway2', 'node1', 'node2', 'node3', 'node4',
#                   'node5', 'node6', 'node7', 'node8', 'node9']
```

### 13.5 Backup Sistemleri — İlk Tam Doğrulama

```bash
# pg_receivewal aktif:
systemctl is-active teqlif-pg-receivewal   # → active
ls /opt/teqlif/backups/postgres/wal/       # → .gz.partial dosyası mevcut
# pg_receivewal lag — 0 veya çok küçük:
psql -h 10.10.0.5 -p 5432 -U replicator \
  -c "SELECT slot_name, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes \
      FROM pg_replication_slots WHERE slot_name='wal_backup_node9';"
# → lag_bytes < 10MB (normal çalışma)

# İlk pg_dump manuel çalıştır:
systemctl start teqlif-pg-dump.service
systemctl is-active teqlif-pg-dump.service  # oneshot → inactive (tamamlandı)
ls -lh /opt/teqlif/backups/postgres/dump/  # → .sql.gz dosyası mevcut

# ClickHouse backup manuel çalıştır:
systemctl start teqlif-clickhouse-backup.service
ls /data/clickhouse/backups/               # → ch_backup_* dizini mevcut

# Redis backup manuel çalıştır:
systemctl start teqlif-redis-backup.service
ls /opt/teqlif/backups/redis/              # → core-redis-*.rdb.gz mevcut

# Tüm timer'lar aktif:
systemctl list-timers "teqlif-pg-*" "teqlif-redis-*" "teqlif-clickhouse-*" "teqlif-offsite-*"
# → hepsi active/waiting
```

### 13.6 Alertmanager — Telegram Testi

```bash
# Test alert gönder:
curl -s -X POST http://127.0.0.1:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "warning", "instance": "node9"},
    "annotations": {"description": "Faz 13 doğrulama: node9 Alertmanager çalışıyor."}
  }]'
# → Telegram #ops kanalında mesaj gelmeli (repeat_interval nedeniyle 4 saat sonra tekrarlanmaz)
```

### 13.7 Grafana — Dashboard Doğrulaması

```bash
# Grafana sağlık:
curl -s http://127.0.0.1:3000/api/health | python3 -m json.tool
# → {"commit": "...", "database": "ok", "version": "..."}

# Grafana WireGuard üzerinden erişim (lokal makineden, WG bağlantısı varsa):
# http://10.10.0.13:3000
# Data Sources: Prometheus → http://127.0.0.1:9090  ✓
#               Loki       → http://127.0.0.1:3100  ✓
```

### 13.8 Guardian — node9 Entegrasyon Durumu

```bash
# node5'te Guardian: node9'u görüyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node9
# → cpu_percent, mem_percent, disk_percent_data gibi alanlar güncel

# node9'un guardian_priority: 5 → lider seçilmemeli
redis-cli -h 10.10.0.11 -p 6382 -a <pass> get guardian:leader
# → "node5" veya "node6" (node9 asla lider olmamalı)

# Guardian node9'un ClickHouse component'ini HEALTHY görüyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> \
  hget "edge:health:node9" "clickhouse"
# → "HEALTHY"
```

### 13.9 Faz 13 Son Kontrol Listesi

- [ ] WireGuard: node9 ↔ tüm diğer 10 node çift yönlü handshake OK
- [ ] ClickHouse: prod yazmaları node9'a geliyor (analytics_events satır sayısı artıyor)
- [ ] Prometheus: 11 target UP (node9 dahil)
- [ ] Loki: 11 node'dan log akışı görünüyor
- [ ] pg_receivewal: WAL lag < 10 MB, .gz.partial dosyaları birikmeye devam ediyor
- [ ] pg_dump: ilk dump dosyası mevcut, < 24 saatlik
- [ ] ClickHouse backup: `/data/clickhouse/backups/ch_backup_*` mevcut
- [ ] Redis backup: `/opt/teqlif/backups/redis/` dosyaları mevcut
- [ ] Alertmanager: Telegram #ops kanalına test mesajı gönderildi
- [ ] Grafana: her iki data source (Prometheus + Loki) bağlı, dashboard node9 metriklerini gösteriyor
- [ ] Guardian: node9 lider seçilmedi, edge:metrics:node9 güncel
- [ ] Circuit breaker test: ClickHouse kapatılınca app canlı kalıyor, yeniden açılınca yazma devam ediyor
- [ ] node9 guardian_priority: 5 → redis-cli confirm
- [ ] Off-site rclone bağlantısı: `rclone lsd b2backup:` → bucket görünüyor

---

## Özet Tablo

| Faz | Konu | Önkoşul | Paralel? |
|-----|------|---------|---------|
| 0 | Kod hazırlığı (lokalde) | — | — |
| 1 | OS temeli — tüm node'lar | 0 | — |
| 2 | WireGuard mesh | 1 | — |
| 3 | Rol bazlı sysctl + UFW | 2 | — |
| 4 | Veri katmanı HA (node5 + node6) | 3 | — |
| 5 | Core app (node5 primary + node6 standby) | 4 | — |
| 6 | Storage (node7 + node8) | 5 | ✅ 7, 8 ile |
| 7 | Gateway (gateway1 + gateway2) | 5 | ✅ 6, 8 ile |
| 8 | Stream (node1 + node4) + AI Proxy (node2) | 5 | ✅ 6, 7 ile |
| 9 | Orchestrator | 6 + 7 + 8 | — |
| 10 | Monitoring + Backup + ClickHouse (node9) | 9 | — |
| 11 | Staging (node3) | 10 | — |
| 12 | Prodüksiyon + Mobile | 11 | — |
| 13 | node9 Doğrulama + Tam Entegrasyon | 12 | — |

---

*V2.0 uygulama planı — 02_plan.md · 2026-09-29 (rev63 — V1.4 vs V2.0 servis gap analizi: 4 eksik servis/drop-in eklendi — (1) `systemd/thp-disable.service` paylaşımlı (tüm node'lar, §1.12 `cat >` → `cp`); (2) `systemd/pgbouncer.service.d/restart.conf` paylaşımlı (node5+node6, §4.2 `cat >` → `cp`); (3) `systemd/promtail.service.d/override.conf` paylaşımlı (tüm node'lar, §7.3 `cat >` → `cp`); (4) `node3/systemd/teqlif-worker-critical-staging.service` — staging critical worker (push bildirimleri, outbid, loser cascade; BindsTo=teqlif-staging.service; §11.3'e cp + systemctl enable eklendi) | rev62 — systemd servis dosyaları repoya eklendi: tüm inline heredoc/ini blokları kaldırıldı, per-node ve paylaşımlı systemd/ dizinlerine fiziksel .service/.timer dosyaları oluşturuldu — 46 dosya (node5/6: redis-core/orch/guardian, teqlif, teqlif-worker, teqlif-worker-critical, teqlif-ai-proxy, postgres-exporter, node-exporter; node7/8: minio, node-exporter; node1/4: livekit, node-exporter; node2: teqlif-ai-proxy, node-exporter; node3: teqlif-ai-proxy, redis-staging, teqlif-staging, teqlif-worker-staging, node-exporter, guardian drop-in; node9: pg-receivewal, pg-basebackup+timer, pg-dump+timer, redis-backup+timer, clickhouse-backup+timer, offsite-sync+timer, node-exporter; gateway1/2: node-exporter; paylaşımlı systemd/: teqlif-guardian.service tüm node'larda aynı unit); plan §4-§11 her servis bloğu `cp <repo-path> /etc/systemd/system/` komutuyla değiştirildi; node6 teqlif.service --workers 4→3 (3 core); teqlif-pg-basebackup.service TELEGRAM_CHAT_ID_OPS→TELEGRAM_CHAT_ID | rev61 — .env şablonları + secrets stratejisi: (1) §0.0 Secrets Üretimi bölümü eklendi — 13 paylaşılan secret, üretim komutu ve hangi node'larda kullanıldığı tablosu; ~/teqlif-secrets.env lokal vault formatı tanımlandı; (2) config.py eksik alanlar eklendi: orch_redis_url, guardian_redis_url, ai_proxy_url, minio_endpoint, minio_endpoint_dm, media_host, uploads_host, upload_presign_ttl; use_pgbouncer default False→True; site_url hardcoded default kaldırıldı; clickhouse_db default "default"→"teqlif_prod_analytics"; (3) §0.5 node5/6 template tamamlandı — "# ... Firebase, LiveKit, JWT" comment'i kaldırılıp ~25 key eklendi: SECRET_KEY, LIVEKIT, FIREBASE, BREVO, APNS, GOOGLE, SENTRY, CAPTCHA, ADMIN, TELEGRAM, SITE_URL; CLICKHOUSE_DB ve MINIO_ACCESS_KEY/MINIO_SECRET_KEY eklendi; (4) §0.5 node2 template'e GROQ_API_KEY ve GEMINI_API_KEY eklendi; (5) §0.5 node3 tam staging template eklendi — 60+ key, APNS_USE_SANDBOX=True, CAPTCHA_ENABLED=False, WEB_APP_ENABLED=True, lokal PG/Redis, prod MinIO staging bucket'ları; (6) §0.5 node9 TELEGRAM_CHAT_ID_OPS → TELEGRAM_CHAT_ID (config.py ile tutarlı); CLICKHOUSE_DB eklendi; (7) node3 template adı .env.production.template → .env.staging.template; §0.5 listing güncellendi; (8) §11.3 drop-in eklendi: teqlif-guardian.service.d/staging-env.conf — node3'te guardian varsayılan .env.production yerine .env.staging okur; §11.3 sparse inline .env içeriği §0.5 referansıyla değiştirildi; (9) §0.4 checklist'e minio_endpoint ve minio_endpoint_dm maddeleri eklendi; (10) 11 adet fiziksel template dosyası repoya eklendi: gateway1/2, node1-9 resources/*.env.{production,staging}.template | rev60 — Faz 0 yapısal + presigned 403 + config defaults + env çelişkisi: (1) §0.10/§0.11 sıralama düzeltildi — Cloudflare güvenlik ve mobil kod değişiklikleri §0.9'dan önce geliyordu; §0.9 Doğrulama sonrasına (§0.6-§0.9 peşi sıra) alındı; (2) Presigned PUT 403 riski giderildi: §6.3 minio.service'e `MINIO_SERVER_URL=https://uploads.teqlif.com` eklendi — S3 V4 imzası Host header'ını içerir; MINIO_SERVER_URL olmadan MinIO dahili IP için imzalanmış URL'i uploads.teqlif.com domain'inden reddederdi (403); §0.3.3 presign_put/presign_put_dm fonksiyonlarına zorunluluk notu eklendi; (3) §0.4 config.py temizliğine `edge_livekit_urls` ve `edge_minio_urls` hardcoded fallback default'ları eklendi (node1+node4 WG IP'leri, node7+node8 WG IP'leri) — §0.2.1 orch_client.py 4. kademe fallback bu değerleri kullanır; §0.4'te tanımsız kalırsa config'e düşünce boş liste gelir, topoloji dağılır; (4) §0.5 gateway2 .env açıklama metni düzeltildi — INTERFACE_SPEED_MBPS=4000 değeri .env bağlamında anlatılıyordu; artık node.conf referansı gösteriyor | rev59 — Storage replication + Nginx PUT fix + bağımlılık haritası: (1) §6.4/§6.6 nginx `error_page 404/502/503/504 = @fallback` kaldırıldı → `upstream minio_media/minio_uploads` + `proxy_next_upstream` ile değiştirildi (PUT/POST request body drop bug ortadan kalktı — named location subrequest body'yi kaybediyordu); (2) §6.9 nightly `mc mirror` + `teqlif-storage-sync.service/.timer` kaldırıldı → MinIO Site Replication (aktif-aktif, sürekli, `mc admin replicate add minio7 minio8`) ile değiştirildi; kurulum + test + diff doğrulaması eklendi; presigned PUT tek-node yazma penceresi kapandı; (3) §0.3.3 yorum "Nginx dual-write" → "Nginx fallback yapar — anlık dual-write MinIO Site Replication ile" düzeltildi; (4) Faz 6/7/8 bağımlılık haritası + Önkoşullar "Faz 3 (paralel)" → "Faz 5 tamamlandı" olarak güncellendi (guardian VIP Faz 5 gerektiriyor); §5.7 cross-node guardian kontrol adımı buna göre kaldırıldı; (5) Hayalet referanslar temizlendi: logrotate'den `storage_sync.log` bloğu, §6.10'dan `systemctl is-active teqlif-storage-sync.timer`, §10.6.9 zamanlayıcı tablosundan `teqlif-storage-sync` satırı | rev58 — node3 hayalet dizin + guardian eksikliği + Faz 5/11 doğrulama: (1) §11.3 yanlış "Faz 10.1'de klonlandı" yorumu kaldırıldı — node3 ZAP VA ayrı sunucu; git clone + venv + pip install adımları eklendi; (2) §11.3 `systemctl enable` ve §11.5 doğrulama listesine `teqlif-guardian` eklendi; (3) §5.7 Faz 5 doğrulamasına cross-node guardian bağlantı kontrolü eklendi — paralel kurulumda Faz 5 sonrası storage/gateway/stream node'larının guardian'ı VIP'e bağlandı mı loop ile doğrula | rev57 — Guardian/Upload/Flutter SRE audit: (1) §0.2.1 orch_client.py 3 kademeli fallback → 4 kademeli: Redis → JSON taze → stale JSON (son bilinen topoloji, UDP modunda JSON güncellenmediğinde hardcoded'dan iyidir) → config.py defaults (node1/node4/node7/node8 hardcoded — en sağlam DC'ler); fallback level Prometheus metric olarak yayınlanır; (2) §0.3.2 cleanup_orphaned_storage.py'a grace period zorunluluğu eklendi — MinIO last_modified ≥ 24h şartı; race condition önlemi (DB insert başarısız/MinIO write başarılı senaryosu); (3) §0.3.3 Mobile upload checklist'e 403 Expired URL transparent retry zorunluluğu eklendi — PUT 403 → sessiz yeni /presign → tekrar PUT (tek retry, ikincide hata göster); (4) §0.11 CachedNetworkImage zorunlu cacheKey parametresi belgelendi — eksik bırakılırsa imzalı URL cache key olur, her 15 dakikada yeniden indirme, 14 günlük stalePeriod tasarımı bozulur | rev56 — Yeşil alan audit + SRE düzeltmeleri: Temel Kural 1 genişletildi — "yeşil alan" vurgusu, legacy endpoint varsayımı yok, presigned upload V2.0'dan itibaren tek yöntem, "eski kod bozulur" gerekçesiyle kısıtlama gevşetilmez; gateway client_max_body_size 50m→5m (V2.0 başlangıcından beri, geçiş kodu yok — Faz 12 sed komutu doğrulama adımına dönüştürüldü); §10.6.11 DR tablosuna "Deluxhost DC kesintisi (Kabul Edilen Risk)" satırı eklendi — upload durur, okuma CF+nginx cache'inden devam eder; §4.8 config.d/teqlif.xml'e `max_server_memory_usage = 24 GB` eklendi (query-level users.d limiti background merge/compaction'ı kapsamaz; server-level cap node9 OOM'dan korur, 7 GB Prometheus+Loki+OS için rezerve kalır) | rev55 — SRE audit düzeltmeleri: KRİTİK 1 — §4.3 node5 postgresql.conf'a `max_slot_wal_keep_size = 5GB` eklendi (wal_backup_node9 slot düşerse WAL birikimine 5GB üst sınır — disk dolmaz/PostgreSQL PANIC yok); KRİTİK 2 — §10.0.1 + §10.6.1 node9 dizin kurulumu symlink mimarisine geçti: PG WAL+backup fiziksel olarak `/data/teqlif_backups/` (3.5TB RAID-1)'a, tüm scriptler `/opt/teqlif/backups/` → symlink üzerinden erişir (149.9GB LVM root dolmaz); UYARI 1 — §0.3.2'ye `cleanup_orphaned_storage.py` ARQ job task'ı eklendi + §6.9'a `teqlif-storage-cleanup.service` + `teqlif-storage-cleanup.timer` (aylık, node5'te) eklendi; logrotate'e `storage_cleanup.log` girişi eklendi; UYARI 2 FALSE POSITIVE — node6 `effective_io_concurrency=8` override rev50'de zaten vardı, değişiklik yapılmadı | rev54 — Plan yapısal temizlik: tüm bağımsız "Not:" blokları kaldırıldı (12 adet), içerikler ya ilgili adıma entegre edildi ya da revision history'de mevcut olduğu için çıkarıldı; §6.3'teki mc versioning+ILM bloğu §6.9'a taşındı (mc alias minio7/minio8 alias'larından sonra çalışması gerekiyor, önceden bağımsız "Not:" ile belirtiliyordu); §6.4'e iki server block tasarım açıklaması intro olarak eklendi; wg_vip_node5.sh MASTER script'e WG routing sorumluluğu yorum eklendi — artık her Faz adım adım okunabilir, "not neydi todo neydi" yorumu gereksiz | rev53 — Guardian SRE audit: (1) Nokta 1 GERÇEK BUG: election.py'a Redis backoff eklendi — `redis_unavailable_since` takibi + 20s geçmeden Adım 2'ye (UDP) geçme yasağı; gerekçe: Keepalived tipik ~3-5s'de redis-guardian promote eder; ama kötü senaryoda 15s TTL dolmadan önce UDP election başlarsa ve Redis geri gelirse iki eş zamanlı election oluşur (election thrashing); 20s buffer bu durumu önler; (2) Nokta 2 GERÇEK GAP: UDP fallback lider davranışı belgelendi — salt pasif: Telegram CRITICAL alert at, coordinator_loop başlatma (Redis gerektiren işlemler çalışamaz), routing/playbook/CF DNS yok; coordinator_loop'a election.mode=="udp" guard eklendi; V2.1'e kadar sınır; (3) Nokta 3 FALSE POSITIVE: "GUARDIAN ASLA OTOMATİK DEĞİŞTİRMEZ" kuralı — traffic_eligible insan onayı, Guardian sadece orch:routing:* key'leri değiştirir; node reboot → node.conf değişmez → eligibility korunur; orch-redis routing key'leri bağımsız persist eder; Routing Eligibility bölümüne desired state kalıcılığı açıklaması eklendi; (4) Bağımsız bug: Keepalived notify script notu yanıltıcıydı — "systemctl start/stop teqlif-guardian çağırır" → guardian tüm node'larda her zaman çalışır, notify script onu durdurmaz/başlatmaz; not düzeltildi (wg_vip_failover.sh BACKUP bloğu zaten doğruydu) | rev52 — Cloudflare caching tutarlılığı: node7+node8 nginx minio.conf tek server block'tan iki ayrı server block'a bölündü — `media.teqlif.com` (CF Proxied: set_real_ip_from CF IP ranges, GET/HEAD only, proxy_cache storage_cache 7d, Cache-Control: public max-age=31536000 immutable, 100r/s burst=200) + `uploads.teqlif.com` (DNS Only: limit_conn 10, 10r/s burst=20, proxy_cache off, Cache-Control: no-store); §0.3.3 tablosunda "Media okuma (GET)" satırı DNS Only→CF Proxied CDN edge cache olarak düzeltildi; §6.8 CF DNS tablosu zaten doğruydu; Cloudflare Page Rules 3→4: uploads.teqlif.com/* Bypass eklendi (presigned S3 imzası CF proxy'den geçince bozulur; ileride Proxied'a geçilirse koruma); MinIO tablosu "Her ikisi Cloudflare arkasında" → okuma CF Proxied + CDN cache, yazma DNS Only CF bypass olarak düzeltildi; İki katmanlı cache: CF edge (1 ay Cache Everything) → nginx SSD (7 gün) → MinIO HDD — her iki katman da HDD okuma yükünü azaltır; uploads.teqlif.com presigned GET (DM) no-store ile tarayıcı cache'ini de engeller | rev51 — Upload mimarisi gateway bypass olarak belgelendi: §0.3.3 yeni bölüm eklendi — felsefe (gateway = yalnızca JSON sinyal; byte akışı ilgili node'a direkt) + 3-adım presigned PUT akışı (presign→PUT node7/8 direkt→complete+ARQ) + storage_service.py presign_put/presign_put_dm implementasyon şablonu + DM private bucket akışı + değiştirilecek dosyalar checklist; trafik akışı diyagramı güncellendi (uploads.teqlif.com DNS Only satırı eklendi, gateway bypass notu); §0.4 config'e upload_presign_ttl: int = 900 eklendi; gateway nginx client_max_body_size 50m'ye geçiş notu eklendi (presigned upload tam geçiş sonrası Faz 12'de 5m'ye indirilecek); Faz 12 doğrulamasına presigned upload testi + gateway log kontrolü + client_max_body_size 50m→5m adımı eklendi | rev50 — node6 PostgreSQL disk override: pg_basebackup node5'in postgresql.conf'unu kopyalar; node5 NVMe ayarları `random_page_cost=1.1` ve `effective_io_concurrency=200` node6'ya taşınırdı; node6 Deluxhost diski ~2.5K IOPS (node5 11.6K IOPS'un 5×'i yavaş) — planner "disk çok hızlı" sanıp tüm sorguları index scan'e iter, failover sonrası DB kilitlenir; §4.6 pg_basebackup adımına `cat >> postgresql.conf` override bloğu eklendi: `random_page_cost=4.0` (PostgreSQL varsayılanı — spinning/yavaş disk) + `effective_io_concurrency=8` | rev49 — node5 Python servislerine MemoryMax eklendi: teqlif.service=1500M (4 uvicorn worker yük altında 400MB/worker olabilir; leak → cgroup kill → Restart=always, PG/Redis korunur), teqlif-worker.service=1000M (ARQ ~300MB plan; analytics batch burst için 3× pad), teqlif-worker-critical.service=800M (critical job küçük/hızlı olmalı), teqlif-guardian.service=300M (sadece health check+heartbeat; 300M aşılıyorsa leak kesin); AI proxy zaten 600M'dı — tüm Python servisler artık cgroup ile sınırlı; node5 en kötü eşzamanlı senaryo 1500+1000+800+300=3600M ama her service kendi sınırına ulaşınca kill+restart → gerçek eşzamanlı hit imkânsız; Redis 2.4GB + PG shared_buffers 2GB = sabit 4.4GB → leak hiçbir zaman veritabanlarına ulaşamaz | rev48 — 3 hata giderildi: (1) redis-core.conf `maxmemory-policy allkeys-lru` → `volatile-lru` — ARQ kuyruğu redis-core (6379) üzerinde çalışır; `allkeys-lru` TTL'siz ARQ job hash'lerini bellek dolduğunda sessizce siler (job kaybolur, hata yok); `volatile-lru` yalnızca TTL'li cache key'leri siler — ARQ key'leri (TTL yok) asla evict edilmez; (2) Gateway nginx `api.teqlif.com` server bloğuna `client_max_body_size 50m;` eklendi — nginx varsayılanı 1MB; profil fotoğrafı ve form ekleri için 413 Payload Too Large hatası dönerdi; storage node nginx'te zaten 100m vardı ama gateway seviyesinde kısıtlama vardı; (3) ClickHouse backup disk taşması: clickhouse_backup.sh `-mtime +7` → `-mtime +2` (lokal 2 gün); offsite_sync.sh'e rclone başarısından sonra `find ... -mtime +1 -exec rm -rf` eklendi — node9 3.5TB /data disk günlük büyüyen ClickHouse verisini 7 tam backup + WAL ile taşırabilirdi; off-site B2'de --max-age 7d korundu (uzun dönem B2'de, kısa dönem lokal) | rev47 — wg_vip_failover.sh 3 iyileştirme: (1) Split-brain guard eklendi — MASTER bloğunun başına `ssh node5 exit` probe; erişilebiliyorsa failover abort (node5 yaşıyor, WG link sorunu); bu 2-node Keepalived VRRP'nin temel split-brain riskini azaltır (Patroni/etcd olmadan en basit fencing); (2) Tüm 4 SSH döngüsü senkron→paralel: `& / wait` pattern — 9 node × ConnectTimeout=5s yerine tek bekleme; 2 unreachable node için ~10s gecikme ortadan kalkar; (3) PgBouncer max_client_conn 200→2000 — 200 gereksiz kısıtlayıcı; PgBouncer'ın amacı binlerce client'ı az PG bağlantısına sığdırmak; actual PG bağlantı sınırı default_pool_size=25 (değişmedi). Bug 1 eleştirisi (MASTER bloğunda wg-quick save yok) FALSE POSITIVE — step 7 satır 2535'te zaten vardı | rev46 — 3 hata giderildi: (1) Staging ağ çelişkisi — diagram `node3 :8000 doğrudan` → `gateway → WG → node3:8000`; gateway nginx'e `staging.teqlif.com` upstream+server bloğu eklendi (node3 UFW zaten wg0-only, değişmedi); (2) pg_hba.conf `10.10.0.7/32 teqlif` gereksiz girişi kaldırıldı — PgBouncer `host=127.0.0.1` bağlandığı için PostgreSQL bağlantıyı 127.0.0.1'den görür, 10.10.0.7'den değil; node6 yalnızca replication rolüyle 10.10.0.7/32'den bağlanır; yanlış açıklayan not düzeltildi; (3) Keepalived chk_redis script node5+node6 — `redis-cli -a <pass> ping` → `redis-cli -a <pass> --no-auth-warning ping` (rev43'te guardian node.conf'ta düzeltildi ama Keepalived tarafı atlanmıştı; 2s aralıkta çalışan script STDERR uyarısıyla journald'ı doldururdu) | rev45 — Guardian systemctl sudo yetkisi eksikliği giderildi: §2.6 yeni bölüm eklendi — tüm 11 node'da /etc/sudoers.d/guardian-systemctl (teqlif* için start/stop/restart/reload/reset-failed NOPASSWD) + per-node ek servisler tablosu (pgbouncer/redis/livekit/minio/nginx/prometheus); §0.2.2 ALLOWED_COMMANDS'a implementasyon notu eklendi (systemctl() helper → subprocess(["sudo","systemctl",...]) — direkt çağrı User=tucibeyin altında Permission Denied, Local Healer hiç çalışmazdı) | rev44 — Mimari Referans bölümü eklendi (plan başına §0 öncesi): node özeti + WG mesh IP tablosu, trafik akış diyagramı (gateway/media/stream/staging), uygulama servisleri node×durum matrisi (FastAPI/AI/LiveKit/gateway), veri katmanı HA tabloları (PG+PgBouncer aktif-pasif, Redis 3 instance + guardian direkt-IP açıklaması, MinIO dual-write), HA mod özeti + RTO tablosu, monitoring/backup servisleri, tüm 11 node ortak servisler; redis-guardian'ın VIP değil direkt IP üzerinden replika olmasının nedeni açıklandı | rev43 — Guardian audit: node.conf Redis health check cmd'lerine `-a $VAR --no-auth-warning` eklendi (redis-core/orch/guardian üçü de requirepass — şifresiz redis-cli daima NOAUTH döndürür, guardian tüm Redis'leri sürekli "failed" görürdü); guardian_agent.py cmd health check subprocess(shell=True, env=os.environ) zorunluluğu notu eklendi (shell=False ile $VAR expand olmaz — literal kalır); election keepalive `SET guardian:leader EX 15 NX` → `EXPIRE guardian:leader 15` (NX flag yalnızca key yokken set eder — lider key'i zaten tutar, NX başarısız olur, TTL yenilenemez, 15s'de expire → sürekli yeniden seçim; EXPIRE ile yalnızca mevcut key'in TTL'si uzatılır) | rev42 — Monitoring audit: NodeDown alert expr'e `instance!~"10\\.10\\.0\\.(2|9|8|12):9100"` filtresi eklendi — gateway ve storage node'ları GatewayDown/StorageNodeDown özel alert'leri kapsar; filtre olmasaydı her gateway/storage failure iki ayrı critical Telegram bildirimi gönderirdi; Alertmanager inhibit_rule düzeltildi: `equal: [alertname, instance]` → `source_matchers: NodeDown / target_matchers: warning / equal: [instance]` — eski kural alertname'ler farklı olduğu için hiçbir zaman tetiklenmiyordu (NodeDown critical ≠ Node5HighCPU warning alertname çifti oluşmaz); yeni kural NodeDown tetiklendiğinde aynı instance'ın warning alertlerini suppress eder | rev41 — Backup audit: PITR restore_command `cp` → `gunzip -c %f.gz > %p` (pg_receivewal --compress=9 ile WAL'lar .gz olarak saklanır; PostgreSQL %f'e uzantısız isim geçirir — cp dosyayı bulamazdı, PITR tamamen başarısız olurdu); offsite_sync.sh ClickHouse path `/opt/teqlif/backups/clickhouse/`→`/data/clickhouse/backups/` (clickhouse_backup.sh /data/clickhouse/backups/'e yazıyor — path uyumsuzluğu yüzünden ClickHouse yedekleri hiçbir zaman off-site'a gönderilmiyordu); §10.6.9 başlığı "node3"→"node9" (tüm zamanlayıcılar node9'a kurulur) | rev40 — Backup audit: PITR restore_command `cp` → `gunzip -c %f.gz > %p` (pg_receivewal --compress=9 ile WAL'lar .gz olarak saklanır; PostgreSQL %f'e uzantısız isim geçirir — cp dosyayı bulamazdı, PITR tamamen başarısız olurdu); offsite_sync.sh ClickHouse path `/opt/teqlif/backups/clickhouse/`→`/data/clickhouse/backups/` (clickhouse_backup.sh /data/clickhouse/backups/'e yazıyor — path uyumsuzluğu yüzünden ClickHouse yedekleri hiçbir zaman off-site'a gönderilmiyordu); §10.6.9 başlığı "node3"→"node9" (tüm zamanlayıcılar node9'a kurulur) | rev40 — nginx audit: gateway WebSocket map `'' close`→`'' ''` (boş string) — close göndermek upstream keepalive 32'yi tamamen etkisiz bırakıyordu; her HTTP request yeni TCP bağlantısı açıyordu; storage node7+8 minio.conf `proxy_buffering off` kaldırıldı (nginx dökümantasyonu: buffering kapalıyken proxy_cache çalışmaz — 1GB SSD cache hiç kullanılmıyordu) | rev39 — UFW+LiveKit audit: LiveKit livekit.yaml'a `turn.relay_range_start: 50000` + `relay_range_end: 60000` eklendi — TURN relay portları UFW'deki 50000:60000/udp aralığıyla eşleşmeli; eksik olduğunda relay portları OS ephemeral aralığına (32768+) düşer ve UFW'de açık olmayan portlara isabet eder; tüm diğer UFW kuralları doğru: gateway CF IP kısıtlaması, core WG-only, stream LiveKit portları, storage 80/443, node2/3/9 WG-only | rev38 — Redis service unit audit: cp redis-server.service yaklaşımı kaldırıldı — kopyalanan dosyada PIDFile=/run/redis/redis-server.pid ve RuntimeDirectory=redis tüm üç instance için çakışıyordu (son başlayan servis diğerlerinin PID kaydını eziyordu); her instance için bağımsız cat > ... << EOF ile tam service dosyası yazıldı (RuntimeDirectory=redis-core/redis-orch/redis-guardian, PIDFile yok, StartLimitIntervalSec=300+Burst=5); redis-guardian.conf ve redis-orch.conf'a dir direktifi eklendi (guardian: /var/lib/redis-guardian, appendonly yes verisi /var/lib/redis ile karışmasın; orch: /var/lib/redis-orch); mkdir+chown+chmod redis-orch+guardian dizinleri için eklendi | rev37 — PostgreSQL/PgBouncer/Redis audit: wg_vip_failover.sh MASTER'a `systemctl enable pgbouncer` eklendi (node5'te zaten var — reboot kalıcılığı); BACKUP'a `systemctl disable pgbouncer` eklendi (standby'da yeniden başlamasın); redis-core.conf `requirepass <password>`→`<core_redis_pass>`; redis-orch.conf `requirepass <password>`→`<orch_redis_pass>`; §4.7 `masterauth <password>`→`<core_redis_pass>`/`<orch_redis_pass>`; doğrulama komutları aynı şekilde güncellendi | rev36 — Keepalived/VRRP audit: wg_vip_failover.sh BACKUP branch'e eksik WG routing güncellemesi eklendi (SSH loop tüm non-core node'lara + yerel node6 wg set + wg-quick save — failback sırasında VIP'ler WG routing seviyesinde de node5'e dönmeli); chk_redis script placeholder `<password>`→`<core_redis_pass>` (node5+node6 her ikisinde) | rev35 — Kapsamlı .env + servis audit: GUARDIAN_REDIS_URL tüm 9 .env template'ine eklendi (10.10.0.11:6382 VIP üzerinden; guardian-redis replication direkt IP kullanır ama agent bağlantısı VIP'ten gidebilir); teqlif-guardian.service unit tanımı §5.2'ye eklendi (teqlif-orchestrator+teqlif-metrics'in V2.0 birleşimi, tüm node'larda aynı unit); node5/gateway/stream/storage/node2/node9/staging enable komutları teqlif-metrics→teqlif-guardian; minimal-venv node'larda pip install'a httpx+pyyaml eklendi (guardian_agent.py HTTP health check + node.conf yaml parsing); §7.5/§6.7/§8.3/§10.1 bölüm başlıkları edge_metrics_agent→teqlif-guardian; doğrulama komutları ve checklist teqlif-orchestrator/metrics→guardian; Faz 0 TODO'lardan guardian service ve env ekleme işaretlendi | rev34 — .env audit: node3 staging MINIO_ENDPOINT 10.10.0.7→10.10.0.8 (node6 Core IP, MinIO node7'de); MINIO_ENDPOINT_DM eklendi; node5+node6 template INTERFACE_SPEED_MBPS node6 yorum eklendi | rev33 — Config audit düzeltmeleri: redis-guardian.conf `save "3600 1"` → `save 3600 1` (Redis geçersiz syntax — startup hatası); Prometheus scrape_configs'e node3 (10.10.0.4) eklendi (11 target: 10→11); §4.3 redis-server.service `systemctl disable --now redis-server` eklendi (port 6379 çakışması engeli); `wg_vip_failover.sh` pg_ctl promote'a `pg_is_in_recovery()` guard eklendi (node5 scriptiyle tutarlılık) | rev32 — Ağ topolojisi + güvenlik audit: §3.5 UFW node2+node9 default deny/allow eklendi; §3.5 UFW node3 (Staging) yeni blok eklendi; §2.2 node5 wg0.conf kısayoluna node9 peer eklendi (explicit); §10.0.3 node9 wg0.conf MTU=1420 eklendi; §2.4 ping loop notuna node9 Faz 10 açıklaması eklendi; §7.3 "10 node"→"11 node" + IP listesine node9=10.10.0.13 eklendi; §7.3 Promtail notu "node3'te"→"node9'da" düzeltildi; §4.5 SSH key hedef listesine node9 eklendi; §4.6 pg_hba.conf WAL-replication uyarısı eklendi; §10.6.1 node6 pg_hba.conf güncelleme adımı + failover SSH key eklendi | rev31 — node9 tamamlama: §0.5 node9 .env template eklendi; §1.4 node9 node.conf örneği + guardian_priority=5 eklendi; §4.8 kurulum sırası notu; Faz 10'a §10.0 Ön Kurulum (OS+/data dirs+WireGuard+node.conf+ClickHouse) eklendi; Faz 13 tam bölümü eklendi (WG mesh, ClickHouse prod veri akışı, Prometheus 11 target, Loki 11 node, backup doğrulama, Alertmanager test, Grafana, Guardian entegrasyon, 15 maddelik kontrol listesi); Özet tablo Faz 12/13 sırası düzeltildi | rev30 — node9 entegrasyonu: node9 (10.10.0.13, OVH KS-1-B) eklendi; node3 rol: Monitor+Staging→Staging; ClickHouse node5→node9; Faz 10 Monitoring+Backup+ClickHouse node3→node9; Prometheus scrape+alert node9; Loki listen_address+push_url node9; pg_hba.conf node3→node9; wal_backup_node3→wal_backup_node9; clickhouse_backup.sh lokal (rsync+SSH kaldırıldı); Faz bağımlılık haritası Faz 13 eklendi; failover for loop+ALL_WG_IPS node9; node9 WG peer template; §2.5 sudoers node9; §3.5 Monitor node9; guardian-redis REPLICAOF NO ONE fix (rev29 önceden); LiveKit reconnect fix (rev29); orch_client 3-level fallback (rev29); atomic write guardian_state.json (rev29); UDP election V2.0 simple priority notu (rev29) | rev18 — Tutarlılık + config audit: node5/6 .env metrics alanları eklendi; gateway2 INTERFACE_SPEED_MBPS=4000 ayrı blok; Faz 6.10 fallback test nginx portuna çevrildi; §10.5 duplicate Telegram bildirimi kaldırıldı | rev19 — Dizin izin audit: /var/log/teqlif 750→755; ClickHouse backup dir 755+usermod; /etc/livekit mkdir; /etc/ssl/teqlif node7/8 mkdir; promtail SupplementaryGroups override+__path__ glob; redis_backup BGSAVE+rsync→redis-cli --rdb; backup logrotate node3+node5 | rev20 — Node cross-erişim audit: §2.5 tüm non-core node'larda wg sudoers eklendi; failover step7 sudo bash→wg-quick save; node5 clickhouse-backup sudoers+script sudo rm -rf; postgres_exporter Environment→EnvironmentFile+DATA_SOURCE_NAME env template; Faz 11.4 /etc/ssl/teqlif mkdir eklendi | rev21 — Failover strateji audit: node5 keepalived nopreempt+notify_master/backup eklendi; wg_vip_node5.sh tanımlandı; node6 keepalived.conf vrrp_script blokları eklendi; §5.6 test sadeleştirildi; §5.6.1 failback 6-adım prosedüre dönüştürüldü (keepalived disable→sync→node6 stop→node5 MASTER); §10.6.2 WAL gap uyarısı+pg_basebackup zorunluluğu | rev22 — Dizin yapısı audit: header rol-bazlı ayrıştırıldı (gateway/core/stream/storage/monitoring); /var/log/teqlif 750→755 header düzeltildi; /etc/keepalived/secrets/ chmod 700 eklendi (node5+node6); .env.production chown tucibeyin:tucibeyin 6 node'da eksikti eklendi (node6/node7/gateway1-2/node1/4/node2/node3) | rev23 — Cross-node kesinti kurtarma: §5.6.2 failover WG routing reconciliation prosedürü eklendi; clickhouse_backup.sh STATUS check+cleanup trap eklendi (node5 stale backup birikimi önlendi); pg_basebackup/pg_dump/redis_backup atomik write pattern eklendi (temp→rename) | rev24 — Failsafe audit: nginx Restart=always drop-in (gateway1/2+node7/8); PgBouncer Restart=always drop-in (node5); teqlif/worker/orchestrator StartLimitIntervalSec=300+Burst=10 eklendi; node_exporter --collector.systemd eklendi; Prometheus ServiceFailed+MonitorDiskHigh alert eklendi; DR tablosuna bilinen SPOF'lar+crash-loop recovery eklendi | rev25 — AI Proxy HA: node2→node3→node5 öncelik zinciri; §5.3.1 node5 teqlif-ai-proxy disabled (son çare); §8.5 node3 teqlif-ai-proxy always-on (ilk yedek); §9.2 ai_proxy:active_url doğrulama eklendi; §9.5 AI proxy failover simülasyonu eklendi; DR tablosunda node2 SPOF kaldırıldı → node2+node3 eş zamanlı satırı eklendi; wg_vip_failover.sh MASTER: redis-cli REPLICAOF NO ONE eksikliği düzeltildi (config değişikliği yetmez, live promote şart); failover.env CORE_REDIS_PASS eklendi | rev26 — leader.py kaldırıldı (clean architecture: mechanism duplication — Keepalived zaten lider seçimi yapıyor; Redis lock aynı garantiyi tekrar etmemeli); §0.6'ya tasarım kararı notu eklendi; wg_vip_failover.sh'den orchestrator:leader DEL kaldırıldı; §9.2 doğrulama orchestrator:leader→systemctl is-active ile güncellendi | rev27 — Guardian mimarisi: §0.2 edge_metrics_agent→guardian_agent (local agent+heartbeat+election+command executor); §0.6 orchestrator→Guardian koordinatör (topology-driven, component:env bazlı service state: HEALTHY/DEGRADED/DOWN, job state machine+checkpoint+resume, playbook sistemi, local state cache guardian_state.json, dağıtık lider seçimi Redis NX+UDP peer fallback); §1.4 node.conf YAML full self-description şeması (guardian_priority, network, hardware, components[]); §4.4.1 guardian-redis port 6382 (appendonly yes — job checkpoint kalıcı); tüm node UFW'ye UDP 9901 guardian heartbeat kuralı eklendi; teqlif-orchestrator.service → teqlif-guardian.service geçiş notu | rev28 — traffic_eligible + traffic_type alanları: node.conf her componente eklendi (default: false — insan onayı olmadan routing yapılmaz); routing eligibility kuralı §0.6'ya eklendi (4 şart: eligible+env+systemd+health); internal_mesh/gateway_proxied/direct_internet tipleri; component asla hybrid değildir notu; §0.6 routing modülüne is_routing_eligible() kuralı eklendi)*
