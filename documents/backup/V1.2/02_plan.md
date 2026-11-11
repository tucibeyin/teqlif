# teqlif V1.2 — node101 Cluster Alım & Offsite Backup Uygulama Planı

**Tarih:** 11 Kasım 2026  
**Durum:** 🔵 Planlama — karar ve dosya listesi kilitlendi, uygulama başlamadı  
**Referans Bulgu Belgesi:** [`01_findings.md`](01_findings.md) (34 bulgu, 36 adım)  
**Hedef Node:** `node101` — `195.206.234.142` — DELUXHOST AS214677, Kerkrade NL

---

## 📌 İçindekiler

1. [Hedef ve Kapsam](#1-hedef-ve-kapsam)
2. [node101 Cluster Alım Mimarisi](#2-cluster-alım-mimarisi)
   - [2.1 WireGuard Partial Mesh Topolojisi](#21-wireguard-partial-mesh-topolojisi)
   - [2.2 node101 Servis Envanteri](#22-node101-servis-envanteri)
   - [2.3 Gossip & teqlif-agent Yapısı](#23-gossip--teqlif-agent-yapısı)
3. [Veri Aktarımı Mimarisi](#3-veri-aktarımı-mimarisi)
   - [3.1 Transport Katmanı](#31-transport-katmanı)
   - [3.2 Backup Motoru: restic + rest-server](#32-backup-motoru-restic--rest-server)
   - [3.3 Depolama Modeli: Üzerine Yazma mı, Ekleme mi?](#33-depolama-modeli-üzerine-yazma-mı-ekleme-mi)
   - [3.4 nginx veya Başka Web Bileşeni Gerekli mi?](#34-nginx-veya-başka-web-bileşeni-gerekli-mi)
   - [3.5 İki Ayrı Kimlik Bilgisi: Şifreleme vs Auth](#35-i̇ki-ayrı-kimlik-bilgisi-şifreleme-vs-auth)
4. [Kilitli Kararlar](#4-kilitli-kararlar)
5. [Dosya Değişiklik Listesi](#5-dosya-değişiklik-listesi)
   - [5.1 Yeni Dosyalar — node101/ dizini](#51-yeni-dosyalar--node101-dizini)
   - [5.2 Yeni Dosyalar — node2 & scripts](#52-yeni-dosyalar--node2--scripts)
   - [5.3 Güncellenen Dosyalar](#53-güncellenen-dosyalar)
6. [Bootstrap Süreci](#6-bootstrap-süreci)
7. [Doğrulama Kontrol Listesi](#7-doğrulama-kontrol-listesi)
8. [Güncelleme Günlüğü](#8-güncelleme-günlüğü)

---

## 1. Hedef ve Kapsam

### Ne yapılıyor?
`node101` teqlif cluster'ına **offsite backup alıcısı** olarak entegre ediliyor. `node2`'deki tüm backup verilerinin şifreli, append-only kopyası `node101`'de tutulacak.

### Kapsam sınırları
- node101 üzerinde **uygulama servisleri ÇALIŞMAZ** (PG, Redis, MinIO, FastAPI, ARQ, LiveKit yok)
- node101 yalnızca backup veri deposu + cluster sağlık katılımcısı rolündedir
- Bu plan **Faz 0 + Faz 1 Adım 9–13** kapsamındadır (01_findings.md referans alınır)
- Faz 2–3 (ClickHouse, DR runbook, WORM arşiv vb.) ayrı planlama gerektirir

---

## 2. Cluster Alım Mimarisi

### 2.1 WireGuard Partial Mesh Topolojisi

> **Karar K-WG (kilitli):** node101 **tam mesh'e girmez**; yalnızca `node2` ve `nodeMonitor` ile peer kurar.

Gerekçe: node1/3/4/5/6 gibi uygulamalara hizmet veren node'ların backup alıcısına doğrudan erişmesi gereksiz blast-radius yaratır. node101 `10.10.0.101` adresinde yalnızca iki servis sunar: `8000` (restic rest-server, sadece `node2`'ye açık) ve `9100` (node_exporter, sadece `nodeMonitor`'a açık).

```
[node1 10.10.0.1]  ──────── tam mesh ────────  [node2 10.10.0.2]
[node3 10.10.0.3]  ──────── tam mesh ────────  [node2 10.10.0.2]
...                                                    │
                                      WireGuard       │   port 8000 (restic push)
                                      partial          │
                                                 ┌─────▼──────┐
                                                 │  node101   │
                                                 │ 10.10.0.101│
                                                 └─────┬──────┘
                                                       │   port 9100 (Prometheus)
                                                       │   port 19100 (gossip)
                                              WireGuard│
                                                 ┌─────▼───────┐
                                                 │ nodeMonitor │
                                                 │ 10.10.0.99  │
                                                 └─────────────┘
```

**Mevcut mesh'te yapılacak değişiklikler:**
- `node2` wg0.conf: node101 peer eklenir (`AllowedIPs 10.10.0.101/32`, `PersistentKeepalive 25`)
- `nodeMonitor` wg0.conf: node101 peer eklenir (node_exporter + gossip için)
- `node101` wg0.conf: node2 + nodeMonitor peer'ları (tam dosya oluşturulur)
- `wg_mesh_apply.sh`: dokunulmaz — node1-6 tam mesh için korunur
- **Yeni script:** `wg_add_node101.sh` — sadece node2 ve nodeMonitor'a node101 peer ekler

**`secrets.env.template`'e eklenmesi gerekenler:**
```ini
# node101 (DELUXHOST AS214677 NL, 10.10.0.101 — Offsite Backup)
node101_public_ip=195.206.234.142
node101_pubkey=                      ← bootstrap sonrası doldurulur

# nodeMonitor (Netcup Nuremberg DE, 10.10.0.99 — Monitor)
nodemonitor_public_ip=               ← canlıdan öğrenilecek (açık!)
nodemonitor_pubkey=                  ← canlıdan öğrenilecek (açık!)
```

> **⚠️ AÇIK:** nodeMonitor'ın public IP'si ve WireGuard public key'i `secrets.env.template`'te yok. Bootstrap öncesi `ssh nodeMonitor "curl -s ifconfig.me && cat /etc/wireguard/pubkey"` ile öğrenilecek.

---

### 2.2 node101 Servis Envanteri

| # | Servis | Port (WG) | Açıklama |
|---|--------|-----------|----------|
| 1 | `wg-quick@wg0` | 51820/udp (public) | WireGuard VPN — partial mesh |
| 2 | `restic-rest-server` | 10.10.0.101:**8000**/tcp | Backup HTTP repo — `--append-only --private-repos` |
| 3 | `prometheus-node-exporter` | 10.10.0.101:**9100**/tcp | Sistem metrikleri — Prometheus scraping |
| 4 | `teqlif-agent` | 10.10.0.101:**19100**/tcp | Gossip mesh + watchdog |
| 5 | `teqlif-offsite-prune.timer` | — | Pazar 08:00 UTC — `restic forget --prune` (node101 yerel) |
| 6 | `teqlif-offsite-verify.timer` | — | Haftalık — `restic check --read-data-subset=5%` |

**UFW kuralları (node101):**
```
default deny incoming
default allow outgoing
allow 22/tcp                           ← SSH (key-only; fail2ban koruması altında)
allow 51820/udp                        ← WireGuard (yetkisiz paketler crypto katmanında sessizce düşer)
allow in on wg0 from 10.10.0.2   port 8000  proto tcp  ← restic (node2 only)
allow in on wg0 from 10.10.0.99  port 9100  proto tcp  ← node_exporter (nodeMonitor only)
allow in on wg0 from 10.10.0.2   port 19100 proto tcp  ← gossip (node2)
allow in on wg0 from 10.10.0.99  port 19100 proto tcp  ← gossip (nodeMonitor)
```

**SSH sertleştirme (`/etc/ssh/sshd_config`):**
```ini
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers tucibeyin
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 20
```

**fail2ban (`/etc/fail2ban/jail.d/sshd.conf`):**
```ini
[sshd]
enabled  = true
port     = ssh
maxretry = 5
bantime  = 1h
findtime = 10m
```

> **Güvenlik notu:** `restic-rest-server` hem UFW (`from 10.10.0.2`) hem de `--listen 10.10.0.101:8000` (WireGuard IP bind) çift güvenceyle public internet'ten tamamen izole edilmiştir.

---

### 2.3 Gossip & teqlif-agent Yapısı

**node101 teqlif-agent config (`node101/config/node101.yaml`):**
```yaml
node_id:      node101
priority:     10          # düşük öncelik — backup-only, lider adayı değil
wg_ip:        10.10.0.101
gossip_port:  19100
gossip_token: "..."       # cluster genelinde aynı token

redis_url: ""             # node101'de Redis yok — gossip-only mod
cycle_interval: 60

monitor_services: ["restic-rest-server"]   # sadece kendi servisi

peers:
  - {id: nodeMonitor, priority: 1, wg_ip: "10.10.0.99"}
  - {id: node2,       priority: 2, wg_ip: "10.10.0.2"}
```

**Redis bağımlılığı:**
- node101'de Redis **yoktur**
- teqlif-agent `redis_url: ""` ile gossip-only modda çalışır (job_ok atlamaz — servis yok)
- `offsite_sync` ve `offsite_wal_sync` job_ok'larını **node2**'nin script'i node2'nin Redis'ine yazar → node2 agent'ı izler
- node101 agent'ı yalnızca `restic-rest-server` systemctl sağlığını + gossip heartbeat'ini izler

**Mevcut `node2.yaml`'a eklenecek peer:**
```yaml
  - {id: node101, priority: 10, wg_ip: "10.10.0.101"}
```

**`prometheus.yml`'a eklenecek scrape target:**
```yaml
  - job_name: 'node101'
    static_configs:
      - targets: ['10.10.0.101:9100']
        labels: { node: node101, role: offsite-backup }
```

---

## 3. Veri Aktarımı Mimarisi

### 3.1 Transport Katmanı

```
node2 (Saarbrücken DE)                     node101 (Kerkrade NL)
─────────────────────                      ─────────────────────
10.10.0.2                 WireGuard         10.10.0.101
                       ───────────────►
                       Şifreli tünel        
                       ~12.5ms RTT          
                       ~1 Gbps kapasite     
                       (ölçüldü: specs.md)
```

- Tüm backup trafiği WireGuard şifreli tünel üzerinden akar
- Public internet'e açık port: yalnızca 51820/udp (WireGuard kendisi)
- `restic-rest-server` **yalnızca** `10.10.0.101:8000` (WG interface) dinler → public IP'de erişilmez

---

### 3.2 Backup Motoru: restic + rest-server

**node2 tarafı (push):**
```bash
restic \
  --repository "rest:http://10.10.0.101:8000/teqlif-backup" \
  --password-file /project/teqlif/config/restic.pass \
  backup /project/teqlif/backups/ \
  --tag daily-full \
  --pack-size 32 \
  --exclude "*.partial" --exclude "*.tmp" --exclude ".last_*" \
  --exclude "pg_wal/*.partial" \
  --compression max
```

**node101 tarafı (rest-server):**
```bash
restic-rest-server \
  --path /mnt/data/restic-repo \
  --listen 10.10.0.101:8000 \
  --htpasswd-file /etc/teqlif-offsite/htpasswd \
  --append-only \
  --private-repos
```

**Saatlik WAL push (node2, ayrı servis):**
```bash
restic \
  --repository "rest:http://10.10.0.101:8000/teqlif-backup" \
  --password-file /project/teqlif/config/restic.pass \
  backup /project/teqlif/backups/pg_wal/ \
  --tag pg_wal \
  --pack-size 32 \
  --exclude "*.partial" \
  --compression max
```

**Prune (node101 yerel, Pazar 08:00 UTC):**
```bash
# --tag daily-full: GFS politikası
restic forget --tag daily-full \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# --tag pg_wal: kısa süreli PITR penceresi
restic forget --tag pg_wal \
  --keep-within 7d --prune
```

---

### 3.3 Depolama Modeli: Üzerine Yazma mı, Ekleme mi?

**Cevap: Asla üzerine yazılmaz — append-only içerik-adresli depolama.**

restic her veri bloğunu SHA-256 hash'ine göre adreslenen pack dosyalarına yazar:
1. İlk backup: tüm veriler pack dosyalarına paketlenir → `/mnt/data/restic-repo/data/`
2. İkinci backup: yalnızca yeni/değişen bloklar yazılır (deduplication)
3. Üçüncü backup: aynı blok içeriyorsa hiçbir şey yazılmaz
4. Mevcut pack dosyaları → **asla değiştirilmez** (SHA-256 bütünlüğü bozulur)

`--append-only` modunda:
- `node2` sadece yeni veri yazabilir (HTTP POST)
- `node2` eski verileri silemez, değiştiremez (HTTP DELETE/PUT → 403 Forbidden)
- `forget --prune` → yalnızca `node101` yerel timer'ından çalışır
- Fidye yazılımı senaryosu: node2 ele geçirilse bile node101'deki geçmiş snapshot'lar silinmez

---

### 3.4 nginx veya Başka Web Bileşeni Gerekli mi?

**HAYIR — gerekli değil.**

| Bileşen | Neden Yok? |
|---------|-----------|
| nginx | restic-rest-server kendi HTTP sunucusudur |
| TLS/HTTPS | WireGuard şifrelemesi transport güvenliğini sağlar; dahili trafikte ek TLS gereksiz |
| Load balancer | Tek kaynak (node2) → tek hedef (node101), yük dengeleme gereksiz |
| Reverse proxy | rest-server doğrudan WG arayüzünde dinler, dış dünyaya proxy gerekmez |
| Caddy/Traefik | Yok — public servis değil |

Tek HTTP bileşeni: **`restic-rest-server`** (Go tabanlı, düşük bellek, `~10 MB`).

---

### 3.5 İki Ayrı Kimlik Bilgisi: Şifreleme vs Auth

Restic mimarisinde iki bağımsız sır vardır:

| Sır | Amaç | Lokasyon (node2) | Lokasyon (node101) |
|-----|------|-----------------|-------------------|
| `RESTIC_PASSWORD` | Veri şifreleme (AES-256-CTR) — backup içeriğini şifreler | `/project/teqlif/config/restic.pass` (chmod 400) | Yok — alıcı node şifreyi bilmez |
| `RESTIC_REST_PASSWORD` | HTTP Basic Auth — rest-server'a erişim | `.env.backup`'ta | `/etc/teqlif-offsite/htpasswd` (bcrypt hash) |

> **Key Escrow zorunluluğu:** `RESTIC_PASSWORD` kaybolursa `node101`'deki tüm veriler ebediyen kilitlenir. En az 2 kopyası sunucu dışında tutulacak (password manager + offline USB/kağıt).

---

## 4. Kilitli Kararlar

Önceki tartışmalar ve canlı ölçümler doğrultusunda tüm tasarım kararları kilitlenmiştir.

| # | Karar Alanı | Kilitli Nihai Karar | Gerekçe |
|---|------------|--------------------|---------| 
| **D1** | WireGuard topoloji | **Partial mesh**: node2 + nodeMonitor ONLY | Blast-radius; node1/3/4/5/6 backup alıcısına erişmez |
| **D2** | rest-server kullanıcısı | **Yeni sistem kullanıcısı `teqlif-backup`** | En az yetki ilkesi; `tucibeyin` interactive user |
| **D3** | WireGuard yardımcı script | **Ayrı `wg_add_node101.sh`** | `wg_mesh_apply.sh` node1-6 tam mesh için korunur; partial logic karışmasın |
| **D4** | teqlif-agent Redis | **Boş — gossip-only mod** | node101'de Redis yok; job_ok node2'nin Redis'ine yazılır |
| **D5** | rest-server auth kullanıcı adı | **`teqlif-offsite`** | Açıklayıcı; `node2` değil (gelecekte başka kaynak eklenebilir) |
| **D6** | Restic şifre lokasyonu | **`/project/teqlif/config/restic.pass`** (node2) | `.env.backup`'tan ayrı, 400 perms, daha güçlü izolasyon |
| **D7** | rest-server TLS | **Yok — WireGuard yeterli** | Dahili tünel trafiği; ek TLS overhead gereksiz |
| **D8** | Daily-full zamanı | **06:30 UTC** | Son backup (pg_wal_cleanup `06:20`) + 10dk buffer; apt-daily-upgrade `07:45`'ten önce biter |
| **D9** | Saatlik WAL zamanı | **`*:45 UTC`** | Her saatin 45. dakikası; PG WAL segment genellikle XX:XX kapatılır |
| **D10** | Prune zamanı | **Pazar 08:00 UTC** | Hafta sonu, iş saatleri dışı; `apt-daily-upgrade 07:45+` sonrasında |
| **D11** | Restic versiyonu | **`0.18.0`** (Debian 13 paket) | Debian 13 `apt install restic restic-rest-server` ile native gelir; binary download yok |
| **D12** | Restic --pack-size | **32 MiB** | specs.md fio: `fdatasync 83 IOPS` — küçük dosyalar p99=229ms; 32 MiB pack → tek fdatasync |
| **D13** | Prune retention | **daily-full: 7d/4w/6m** · **pg_wal: 7d** | 7 günlük PITR penceresi; 6 aylık snapshot history; 2.9GB RAM altında güvenli |
| **D14** | nodeMonitor WG entegrasyonu | **node101 ↔ nodeMonitor doğrudan peer** | Prometheus scraping için zorunlu; gossip için de ideal |

---

## 5. Dosya Değişiklik Listesi

### 5.1 Yeni Dosyalar — `deploy/scale/V2.1/node101/` dizini

```
deploy/scale/V2.1/node101/
├── specs.md                                    ✅ mevcut
├── config/
│   └── node101.yaml                            ← teqlif-agent config
├── resources/
│   ├── env/
│   │   └── restic.env.template                 ← .env.backup eklenecek alanlar
│   ├── scripts/
│   │   ├── restic_prune.sh                     ← GOGC/GOMEMLIMIT + MemoryMax koruması
│   │   └── restic_verify.sh                    ← --read-data-subset=5% haftalık check
│   └── wireguard/
│       └── wg0.conf.template                   ← <node2_pubkey>, <nodemonitor_pubkey> placeholder
├── systemd/
│   ├── restic-rest-server.service              ← teqlif-backup user, /mnt/data/restic-repo
│   ├── teqlif-offsite-prune.service            ← oneshot, MemoryMax=2G, GOGC=20
│   ├── teqlif-offsite-prune.timer              ← Pazar 08:00 UTC
│   ├── teqlif-offsite-verify.service           ← oneshot, --read-data-subset=5%
│   └── teqlif-offsite-verify.timer             ← Pazar 09:00 UTC (prune sonrası)
└── bootstrap_node101.sh                        ← idempotent Debian 13 kurulum
    # Adımlar:
    # 1. apt update + restic restic-rest-server prometheus-node-exporter wireguard ufw fail2ban
    # 2. timedatectl set-timezone UTC
    # 3. useradd -r -s /sbin/nologin teqlif-backup
    # 4. mkdir -p /mnt/data/{restic-repo,tmp,cache/restic,logs}
    #    chown -R teqlif-backup:teqlif-backup /mnt/data/{restic-repo,tmp,cache/restic,logs}
    # 5. /etc/fstab kontrol — /mnt/data otomatik mount
    # 6. WireGuard: wg0.conf template doldur + wg-quick@wg0 enable
    # 7. /etc/teqlif-offsite/ dizini + htpasswd oluştur
    # 8. systemd unit dosyalarını deploy/scale/V2.1/node101/systemd/'dan kopyala
    # 9. SSH sertleştirme: sshd_config (PasswordAuthentication no, AllowUsers tucibeyin,
    #    PermitRootLogin no, MaxAuthTries 3, LoginGraceTime 20) + systemctl restart sshd
    # 10. fail2ban: /etc/fail2ban/jail.d/sshd.conf (maxretry 5, bantime 1h) + enable
    # 11. UFW kuralları
    # 12. teqlif-agent kur + node101.yaml deploy
    # 13. Tüm servisleri enable + start
    # 14. echo node101 WG pubkey → secrets.env.template talimatı
```

---

### 5.2 Yeni Dosyalar — `node2` & `scripts`

```
deploy/scale/V2.1/
├── scripts/
│   └── wg_add_node101.sh                       ← node2 ve nodeMonitor'a node101 peer ekler
│
└── node2/
    ├── resources/
    │   └── scripts/
    │       └── offsite_wal_sync.sh             ← saatlik WAL push (--tag pg_wal, --pack-size 32)
    └── systemd/
        ├── teqlif-offsite-wal.service           ← oneshot, OnFailure=, IOSchedulingClass=idle
        └── teqlif-offsite-wal.timer             ← OnCalendar=*-*-* *:45:00 UTC
```

---

### 5.3 Güncellenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `node2/resources/scripts/offsite_sync.sh` | rclone bloğu kaldırılır; `restic backup --tag daily-full --pack-size 32` eklenir; job_ok Redis'e yazılır; `exit 2` (SKIP yerine alarm) |
| `node2/systemd/teqlif-offsite-sync.service` | Description güncellenir ("B2" → "node101 restic"); `OnFailure=teqlif-backup-failed@%n.service` eklenir; `IOSchedulingClass=idle Nice=19` eklenir |
| `node2/systemd/teqlif-offsite-sync.timer` | `OnCalendar` `07:00` → **`06:30 UTC`** |
| `secrets.env.template` | `node101_public_ip`, `node101_pubkey`, `nodemonitor_public_ip`, `nodemonitor_pubkey`, `restic_rest_password` alanları eklenir |
| `documents/01_architecture.md` | §2 node envanterine node101 eklenir; §3.6 backup flow şeması güncellenir; §12 zamanlama tablosu güncellenir |
| `nodeMonitor/config/teqlif/prometheus.yml` | `node101` scrape job eklenir (`10.10.0.101:9100`, role: offsite-backup) |
| `teqlif-agent/configs/node2.yaml` | `peers` listesine `{id: node101, priority: 10, wg_ip: "10.10.0.101"}` eklenir |
| `scripts/bootstrap_node2.sh` | `systemctl enable` listesine tüm 11 timer + `teqlif-offsite-wal.timer` + `teqlif-redis-failover.timer` eklenir |
| `schedule.yaml` | `backup:` anahtarı altına `offsite_sync (watchdog_m: 1500)` + `offsite_wal_sync (watchdog_m: 90)` eklenir |
| `teqlif-agent/modules/health.py` | `_BACKUP_MAX_MIN` / `_backup_ages`'e `offsite_sync (25*60)` + `offsite_wal_sync (90)` eklenir |

---

## 6. Bootstrap Süreci

Ön koşul: `node101`'de `/var/www/teqlif.com` monorepo hazır ✅ (SSH ile doğrulandı).

```
Adım 1 — Bilgi toplama (lokal makineden)
  ssh nodeMonitor "curl -s ifconfig.me"       → nodeMonitor_public_ip
  ssh nodeMonitor "sudo cat /etc/wireguard/pubkey" → nodemonitor_pubkey
  → secrets.env'e ekle

Adım 2 — Monorepo güncelle (node101)
  ssh node101 "cd /var/www/teqlif.com && git pull"

Adım 3 — secrets.env hazırla (lokal)
  node101_pubkey alanı henüz boş — bootstrap sonrası doldurulacak
  Diğer tüm alanlar (restic_rest_password, gossip_token, Telegram) dolu olmalı

Adım 4 — Bootstrap çalıştır (node101)
  scp secrets.env tucibeyin@node101:/tmp/teqlif-secrets.env
  ssh node101 "SECRETS_FILE=/tmp/teqlif-secrets.env \
    bash /var/www/teqlif.com/deploy/scale/V2.1/node101/bootstrap_node101.sh"
  # Script biterken WG public key'i ekrana basar

Adım 5 — WG public key'i secrets.env'e ekle (lokal)
  node101_pubkey=<bootstrap çıktısındaki key>

Adım 6 — node2 ve nodeMonitor'a node101 peer ekle (lokal)
  SECRETS_FILE=./secrets.env bash wg_add_node101.sh
  # Script: node2 ve nodeMonitor'da wg set wg0 peer <node101_pubkey> + wg-quick save

Adım 7 — WG bağlantısını doğrula
  ssh node2 "ping -c2 10.10.0.101"           → OK
  ssh nodeMonitor "ping -c2 10.10.0.101"     → OK

Adım 8 — restic repo başlat (node2'den node101'e)
  ssh node2 "RESTIC_REPOSITORY='rest:http://10.10.0.101:8000/teqlif-backup' \
    RESTIC_PASSWORD_FILE=/project/teqlif/config/restic.pass \
    restic init"

Adım 9 — İlk offsite_sync testi (node2)
  ssh node2 "sudo -u tucibeyin bash \
    /var/www/teqlif.com/deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh"
  # ~2.1 GB veri → node101; ilk çalışmada uzun sürebilir

Adım 10 — Snapshot doğrula (node2)
  ssh node2 "RESTIC_REPOSITORY='rest:http://10.10.0.101:8000/teqlif-backup' \
    RESTIC_PASSWORD_FILE=/project/teqlif/config/restic.pass \
    restic snapshots --tag daily-full"

Adım 11 — append-only kontrolü (node2)
  ssh node2 "RESTIC_REPOSITORY='rest:http://10.10.0.101:8000/teqlif-backup' \
    RESTIC_PASSWORD_FILE=/project/teqlif/config/restic.pass \
    restic forget --dry-run latest 2>&1 | grep -i 'forbidden\|403\|append'"
  # 403 Forbidden → append-only çalışıyor ✔

Adım 12 — Monorepo güncellemesi tüm node'lara (ADR §13 Adım 9)
  for node in node1 node2 node3 node4 node5 node6 nodeMonitor node101; do
    ssh $node "cd /var/www/teqlif.com && git pull" &
  done; wait
  sudo teqlif-restart   # paralel for-loop ile tüm node'lar

Adım 13 — Timer'ları enable + start (node2)
  ssh node2 "sudo systemctl enable --now teqlif-offsite-sync.timer teqlif-offsite-wal.timer"
```

---

## 7. Doğrulama Kontrol Listesi

```
SSH & Güvenlik
  [ ] ssh node101 "sudo sshd -T | grep -E 'passwordauth|permitroot|allowusers'" → hardened ✔
  [ ] ssh node101 "systemctl is-active fail2ban"  → active ✔
  [ ] ssh node101 "sudo ufw status verbose"       → 22/tcp, 51820/udp dışı tüm public portlar kapalı ✔

WireGuard
  [ ] ssh node2 "ping -c2 10.10.0.101"           → 0% loss
  [ ] ssh nodeMonitor "ping -c2 10.10.0.101"     → 0% loss
  [ ] ssh node1 "nc -zw2 10.10.0.101 8000"       → FAIL (erişim yok) ✔

rest-server
  [ ] ssh node101 "systemctl is-active restic-rest-server"    → active
  [ ] ssh node2 "curl -sf --user teqlif-offsite:<pass> http://10.10.0.101:8000/" → 200

append-only
  [ ] node2'den restic forget → HTTP 403 ✔
  [ ] node101 yerel restic forget → çalışır ✔

Backup bütünlüğü
  [ ] restic snapshots --tag daily-full → en az 1 snapshot
  [ ] restic snapshots --tag pg_wal    → en az 1 snapshot
  [ ] restic check → "no errors were found"
  [ ] snapshot içinde pg_basebackup dizini var

Prometheus
  [ ] ssh nodeMonitor "curl -sf http://10.10.0.101:9100/metrics | head -1" → "# HELP..."
  [ ] Grafana'da node101 disk/CPU paneli görünür

gossip
  [ ] ssh nodeMonitor "redis-cli HGETALL teqlif:agent:gossip" → node101 kaydı var
  [ ] teqlif-agent node101 Telegram alertleri çalışıyor (test: servis durdur)

Timer'lar
  [ ] systemctl is-enabled teqlif-offsite-sync.timer  → enabled
  [ ] systemctl is-enabled teqlif-offsite-wal.timer   → enabled
  [ ] systemctl is-enabled teqlif-offsite-prune.timer → enabled (node101)
  [ ] systemctl is-enabled teqlif-offsite-verify.timer→ enabled (node101)

Key Escrow
  [ ] restic.pass ≥ 2 sunucu dışı kopyada tutulduğu kullanıcı tarafından onaylandı
```

---

## 8. Güncelleme Günlüğü

| Tarih | Değişiklik |
|-------|-----------|
| 2026-11-11 | İlk sürüm — 14 karar kilitlendi, dosya listesi oluşturuldu |
