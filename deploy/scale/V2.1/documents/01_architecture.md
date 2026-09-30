# teqlif V2.1 — Mimari

## Node Envanteri

| Node | IP (WG) | Public IP | Tip | Lokasyon | Rol |
|------|---------|-----------|-----|----------|-----|
| node1 | 10.10.0.1 | 193.70.46.74 | Bare metal | OVH Gravelines FR | Core — PG, Redis, App |
| node2 | 10.10.0.2 | 135.125.223.43 | Bare metal | OVH Saarbrücken DE | Backup + Monitoring + ClickHouse |
| node3 | 10.10.0.3 | 51.75.74.124 | KVM VPS | OVH Frankfurt DE | LiveKit Streaming #1 |
| node4 | 10.10.0.4 | 135.125.175.223 | KVM VPS | OVH Frankfurt DE | LiveKit Streaming #2 |
| node5 | 10.10.0.5 | 45.146.252.165 | KVM VPS | ZAP Münster DE | Staging + AI Secondary |
| node6 | 10.10.0.6 | 5.249.165.10 | KVM VPS | ZAP Virginia US | AI Primary (Gemini) |
| streaming-N | 10.10.0.2X | - | - | - | LiveKit Streaming #N (plug-and-play) |

WireGuard subnet: `10.10.0.0/24`
Streaming node pool: `10.10.0.20–10.10.0.99`

---

## Trafik Akışı

```
Kullanıcı
  │
  ├── API (JSON/REST/WS) ──→ Cloudflare Proxy ──→ node1 (nginx → FastAPI)
  │
  ├── Media (foto/video/ses/döküman) ──→ uploads.teqlif.com (direkt node1 MinIO)
  │
  ├── Stream (WebRTC) ──→ stream.teqlif.com (direkt node3/node4/streaming-N)
  │
  └── AI istekleri ──→ node6 (primary, Gemini) → node5 (fallback, EU)
```

---

## node1 — Core (Bare Metal NVMe)

**Donanım:** Intel Xeon E-2236 12c/24t, 32GB ECC, 2×512GB NVMe RAID-1

**Servisler:**
- PostgreSQL 17 (primary, lokal — tek node HA yok, node2 WAL arşivi alır)
- PgBouncer (bağlantı havuzu)
- Redis × 3 (core :6379, orch :6380, guardian :6382)
- MinIO (object storage — teqlif + teqlif-dm bucket)
- FastAPI (teqlif app)
- ARQ workers (teqlif-worker, teqlif-worker-critical)
- nginx (reverse proxy + SSL termination)
- Promtail → node2 Loki

**OS Optimizasyonları (NVMe bare metal):**
- `io_scheduler=none` (NVMe donanım kuyruğu kullanır, OS scheduler gereksiz)
- `vm.swappiness=10` (RAM tercih et)
- `vm.dirty_ratio=15, vm.dirty_background_ratio=5` (NVMe hızlı flush)
- THP (Transparent Huge Pages) = `never` (PostgreSQL THP'den nefret eder)
- `kernel.pid_max=4194304`
- `fs.file-max=2097152`
- `net.core.somaxconn=65535`
- `net.ipv4.tcp_max_syn_backlog=65535`
- CPU governor = `performance` (bare metal erişimi var)
- PostgreSQL huge pages: `vm.nr_hugepages` hesaplanarak set edilir
- `ulimit -n 65535` (tüm servisler için)

---

## node2 — Backup + Monitoring + ClickHouse (Bare Metal HDD)

**Donanım:** Intel Xeon D-2123IT 8c/16t, 32GB ECC, 2×4TB HDD RAID-1

**Servisler:**
- ClickHouse (analitik DB — event log, metrics)
- Prometheus (tüm node'ları scrape eder)
- Grafana (dashboard)
- Loki (log aggregation — tüm node'lardan Promtail alır)
- Alertmanager (Telegram bildirimleri)
- pg_receivewal (node1'den WAL stream)
- pg_dump (günlük snapshot)
- pg_basebackup (haftalık full backup)
- Redis backup (günlük RDB snapshot node1'den)
- MinIO backup (günlük mc mirror node1'den → /data/backups/minio/)
- rclone (ofsite — Backblaze B2)
- Promtail (kendi logları)

**OS Optimizasyonları (HDD bare metal):**
- `io_scheduler=mq-deadline` (HDD için sıralı yazım önceliği)
- `blockdev --setra 8192` (readahead artır — sıralı okuma ağır iş)
- `vm.swappiness=10`
- `vm.dirty_ratio=40, vm.dirty_background_ratio=10` (HDD yavaş, daha uzun buffer)
- THP = `never`
- ClickHouse: `ulimit -n 262144, ulimit -c unlimited`
- `/data` mount: `noatime,nodiratime` (gereksiz inode güncelleme yok)

---

## node3, node4 — LiveKit Streaming (KVM VPS)

**Donanım:** 6 vCPU, 11.4GB RAM, 98GB SSD, OVH Frankfurt DE

**Servisler:**
- LiveKit Server
- nginx (TURN/STUN proxy, UDP 443 yönlendirme)
- Promtail → node2 Loki

**LiveKit koordinasyonu:** node1'deki Redis üzerinden (WireGuard mesh)

**OS Optimizasyonları (KVM, WebRTC/UDP yoğun):**
- `net.core.rmem_max=26214400` (UDP receive buffer — medya akışı)
- `net.core.wmem_max=26214400`
- `net.core.rmem_default=1048576`
- `net.core.wmem_default=1048576`
- `net.ipv4.udp_rmem_min=8192`
- `net.ipv4.ip_local_port_range=10000 65535` (LiveKit port aralığı genişlet)
- `net.netfilter.nf_conntrack_max=262144` (eş zamanlı bağlantı)
- `net.core.netdev_max_backlog=5000`
- `vm.swappiness=5` (stream node RAM baskısı tolere etmez)
- THP = `never`

**UFW:**
- 22/tcp (SSH — WG üzerinden)
- 51820/udp (WireGuard)
- 443/tcp+udp (TURN/STUN)
- 7880/tcp (LiveKit API — sadece WG mesh)
- 7881/tcp (LiveKit RTC — sadece WG mesh)
- 50000-60000/udp (WebRTC medya portları)

---

## node5 — Staging + AI Secondary (KVM VPS, EU)

**Donanım:** 4 vCPU, 7.8GB RAM, 49GB SSD, ZAP Münster DE

**Servisler:**
- Staging stack (tam izole): PG, Redis, MinIO, FastAPI, Workers, LiveKit staging
- AI Proxy (secondary — EU içinde, Groq + Gemini fallback)
- Promtail → node2 Loki

**Not:** AI Primary (node6) erişilemez olursa trafik buraya düşer. EU veri sınırı korunur.

**OS Optimizasyonları:**
- Staging için standart uygulama tuning
- `vm.swappiness=20` (4GB swap var, 7.8GB RAM kısıtlı)
- THP = `never`
- `fs.file-max=524288`

---

## node6 — AI Primary (KVM VPS, US)

**Donanım:** 4 vCPU, 3.8GB RAM, 49GB SSD, ZAP Virginia US

**Servisler:**
- AI Proxy (primary — Gemini API erişimi için ABD lokasyonu)
- Promtail → node2 Loki

**Not:** Sadece AI proxy çalışır. Kullanıcı datası bu node'a girmez. Gemini EU kısıtlaması nedeniyle ABD'de.

**OS Optimizasyonları:**
- Minimal — sadece AI proxy
- `vm.swappiness=20`
- THP = `never`

---

## Plug-and-Play Streaming Node Mimarisi

Kapasite dolunca yeni bir streaming node eklemek için tek adım:

```bash
# Lokal makineden:
STREAMING_IP=10.10.0.20 \
NEW_NODE_HOST=<new-server-ip> \
bash deploy/scale/V2.1/scripts/add_streaming_node.sh
```

Script otomatik olarak:
1. Yeni node'da `bootstrap_streaming.sh` çalıştırır
2. WireGuard key çifti üretilir, pubkey alınır
3. Yeni node'un pubkey'i tüm mevcut node'lara dağıtılır
4. Tüm mevcut node'ların pubkey'leri yeni node'a yazılır
5. WireGuard mesh güncellenir, LiveKit otomatik devreye girer

**LiveKit auto-discovery:** Tüm streaming node'lar aynı Redis'e (node1:10.10.0.1:6379) bağlanır. LiveKit kendi içinde node'ları keşfeder, load balancing otomatik.

---

## WireGuard Mesh Topolojisi

```
node1 (10.10.0.1) ←──────────────────────────────→ node2
     │                                               │
     ├──→ node3 (10.10.0.3)                         │
     ├──→ node4 (10.10.0.4)                         │
     ├──→ node5 (10.10.0.5)                         │
     ├──→ node6 (10.10.0.6)                         │
     └──→ streaming-N (10.10.0.20+)                 │
                                                     │
node2 ←──────────────── tüm node'lar ───────────────┘
(Prometheus scrape, Loki log, backup)
```

Full mesh — her node diğer tüm node'lara direkt erişir.

---

## Veri Kalıcılığı ve Yedekleme

| Veri | Birincil | Yedek | Ofsite |
|------|----------|-------|--------|
| PostgreSQL | node1 | node2 WAL stream + pg_dump | B2 rclone |
| Redis | node1 | node2 RDB snapshot | - |
| MinIO (media) | node1 | node2 mc mirror | B2 rclone |
| ClickHouse | node2 | - | B2 rclone |
| Loki logs | node2 | - | - |

---

## Güvenlik Sınırları

- Kullanıcı datası **sadece EU node'larında** (node1–5)
- node6 (US): yalnızca AI proxy, sıfır kullanıcı datası
- WireGuard: tüm iç servis trafiği şifreli mesh üzerinden
- Cloudflare: API trafiği DDoS koruması altında
- UFW: her node'da minimal port açık
