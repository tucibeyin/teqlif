# Teqlif Scale V1.3 — Plan

> **Baseline:** V1.2 aktif (2026-09-10)  
> **Durum:** Planlama / Uygulama aşaması  
> **Hedef:** node3 (Zap-Hosting, Ashburn VA) topolojiye eklenir; birden fazla rol üstlenir.

---

## 1. Motivasyon

V1.2'de node2 (Buffalo) tek AI proxy olarak çalışmaktadır. Eksikler:

| Bulgu | Detay |
|---|---|
| **AI proxy SPOF** | node2 düşerse lokal fallback devreye girer; Gemini erişimi kesilir |
| **Backup yok** | Production veritabanı yedeksiz; node1 disk arızasında veri kaybı riski |
| **Staging node1'de** | teqlif-staging node1 kaynaklarını tüketiyor; prod'dan izole değil |
| **Log seviyesi tutarsız** | INFO log seviyesi yüksek hacim üretiyor; WARNING+ yeterli |

---

## 2. Donanım

### node3 — Zap-Hosting Ashburn (USA)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **Zap-Hosting GmbH** (DE) |
| Lokasyon | Ashburn, Virginia, ABD (Reston VA) |
| Public IP | 5.249.165.10 |
| WireGuard IP | 10.10.0.4 |
| CPU | AMD EPYC 7763, 4 çekirdek @ 2450 MHz |
| RAM | 3.8 GiB (ballooning kapalı) |
| Disk | 25 GB NVMe |
| Ağ | **1 Gbps / 33 TB/ay** |
| Ödeme | **$81.66 — tek seferlik (lifetime)** |
| Satın alma | 2026-09-11 |
| SSH alias | `teqlif-node3` |
| Hostname | `node3` |
| Panel giriş | Her 90 günde bir — takvime hatırlatıcı eklenmeli |

---

## 3. V1.3 ile Gelecek Değişiklikler

| # | Değişiklik | Etki |
|---|---|---|
| 1 | node3 eklendi (Zap-Hosting Ashburn) | Yeni US IP node |
| 2 | WireGuard 4-node mesh | node1 ↔ node2 ↔ node3 ↔ gateway |
| 3 | AI proxy fallback zinciri | node1 → node2 → node3 → node1 local Groq |
| 4 | `ai_proxy_client.py` güncellendi | İkincil proxy URL desteği |
| 5 | node3 AI proxy servisi | `teqlif-ai-proxy-secondary.service` |
| 6 | Backup servisi | node1'den pg_dump + Redis → rsync → node3 (systemd timer) |
| 7 | Backup doğrulama | Periyodik restore testi node3 PostgreSQL'e |
| 8 | Staging node3'e taşındı | node1'den izole tam staging stack |
| 9 | Log seviyesi WARNING+ | `main.py` ve `ai_proxy_main.py`'de INFO kapatıldı |
| 10 | node3 bootstrap scripti | `deploy/scale/resources/node3/bootstrap_node3.sh` |
| 11 | GitHub Actions runner | node3'te self-hosted CI runner (nice to have) |

---

## 4. AI Proxy Fallback Zinciri (Yeni)

```
node1 /generate-description
  └─► node2:8080/generate          (primary — US Buffalo)
        └─► [başarısız]
              └─► node3:8080/generate   (secondary — US Ashburn)
                    └─► [başarısız]
                          └─► node1 local Groq  (son çare — Gemini yok)
```

### `ai_proxy_client.py` değişikliği

Mevcut: tek `NODE2_AI_PROXY_URL`  
Yeni: `NODE2_AI_PROXY_URL` + `NODE3_AI_PROXY_URL` sıralı deneme

---

## 5. Backup Servisi

### Strateji

- **Kaynak:** node1 (PostgreSQL + Redis)
- **Hedef:** node3 `/var/backups/teqlif/`
- **Yöntem:** pg_dump (sıkıştırılmış) + Redis BGSAVE → rsync over WireGuard
- **Sıklık:** Günlük (02:00 UTC)
- **Saklama:** 7 gün
- **Doğrulama:** Haftalık restore testi node3'teki PostgreSQL'e

### Tahmini boyut

| İçerik | Boyut |
|---|---|
| pg_dump (sıkıştırılmış) | ~500 MB – 2 GB |
| Redis RDB | ~50–200 MB |
| 7 günlük toplam | ~4–15 GB |
| 25 GB diskten payı | ~%16–60 |

---

## 6. Staging Stack (node3)

node1'deki `teqlif-staging` node3'e taşınır.

| Servis | node1 (şimdiki) | node3 (hedef) |
|---|---|---|
| FastAPI staging | ✅ çalışıyor | taşınacak — **1 uvicorn worker** |
| ARQ workers (default) | node1'de çalışıyor | node3'te — **2 process** |
| ARQ workers (critical) | node1'de çalışıyor | node3'te — **1 process** |
| PostgreSQL staging | node1 prod DB paylaşımlı | node3'te izole DB |
| Redis staging | node1 prod Redis paylaşımlı | node3'te izole Redis |
| MinIO staging | teqlif-staging bucket | **node1'e WireGuard üzerinden bağlanır** — kopyalanmaz |
| ClickHouse | node1'de | **node1'e WireGuard üzerinden bağlanır** — kopyalanmaz |
| LiveKit | node1'de | **node1'e WireGuard üzerinden bağlanır** — kopyalanmaz |

### node3 RAM tahmini (test kullanıcıları altında)

| Servis | Boşta | ~20 eşzamanlı kullanıcı |
|---|---|---|
| PostgreSQL | ~400 MB | ~600 MB |
| Redis | ~100 MB | ~300 MB |
| FastAPI (1 worker) | ~200 MB | ~250 MB |
| ARQ workers (3 process) | ~520 MB | ~700 MB |
| AI proxy secondary | ~200 MB | ~300 MB |
| Monitoring (Loki+Prometheus+Grafana) | ~500 MB | ~600 MB |
| Sistem | ~400 MB | ~400 MB |
| **Toplam** | **~2.3 GB** | **~3.15 GB** |

3.8 GiB limitinin **%83'ü** — güvenli bant içinde.

---

## 7. Log Seviyesi Değişikliği

**Hedef:** `WARNING` ve üstü — `INFO` kapatılıyor.

Etkilenen dosyalar:
- `backend/main.py` — uvicorn + uygulama log level
- `backend/app/ai_proxy_main.py` — proxy log level
- `backend/app/core/logger.py` — merkezi logger konfigürasyonu

Tahmini etki: günlük log hacmi 34 GB → ~150 MB (1M kullanıcı senaryosunda)

---

## 8. WireGuard Topoloji (Güncellenen)

```
node1 (10.10.0.1) — Frankfurt DE
  ↕
gateway (10.10.0.2) — Nürnberg DE
  ↕
node2 (10.10.0.3) — Buffalo NY USA
  ↕
node3 (10.10.0.4) — Ashburn VA USA  ← YENİ
```

Tüm node'lar birbirine tam mesh bağlantıyla erişir.

---

## 9. Uygulama Sırası

```
[ ] 1. WireGuard — node3 kurulumu + tüm node'lara peer eklenmesi
[ ] 2. AI proxy secondary — node3'te servis + node1'de client güncellenmesi
[ ] 3. Log seviyesi — WARNING+ kodu değişikliği + deploy
[ ] 4. Staging — node3'te PostgreSQL, Redis, MinIO, FastAPI kurulumu
[ ] 5. Backup — systemd timer + rsync + doğrulama scripti
[ ] 6. Monitoring taşınması — Loki+Prometheus+Grafana+alertmanager gateway'den node3'e; gateway'de sadece nginx kalır
       Migration adımları:
       - node3'te Loki+Prometheus+Grafana+alertmanager kur
       - node1/node2/gateway promtail: `clients.url` → http://10.10.0.4:3100/loki/api/v1/push
       - node1/node2/gateway node_exporter → Prometheus scrape hedefi 10.10.0.4:9090
       - Grafana dashboard'ları aktarılır (export → import)
       - gateway'den monitoring servisleri kaldırılır
[ ] 7. Bootstrap scripti — deploy/scale/resources/node3/
[ ] 8. GitHub Actions runner (nice to have)
```

---

## 10. Güvenlik Notları

- node3 WireGuard private/public key → **git'e girmez**
- `NODE3_INTERNAL_TOKEN` → node1 ve node3'te aynı değer (`.env` dosyalarında)
- Backup rsync → WireGuard tüneli üzerinden (plain internet değil)
- node3 SSH → sadece key tabanlı, şifre auth kapatılacak

---

## 11. Donanım Özeti (V1.3)

| Node | Sağlayıcı | Lokasyon | RAM | Disk | Ağ | Roller |
|---|---|---|---|---|---|---|
| node1 | OVHcloud | Frankfurt DE | 11.4 GiB | 98 GB | 2 Gbps/unmetered | Backend, DB, Redis, MinIO, LiveKit |
| node2 | VPSHostingService | Buffalo NY | 1 GB | 25 GB | 1 Gbps | AI Proxy (primary), CF Failover |
| node3 | Zap-Hosting | Ashburn VA | 3.8 GiB | 25 GB | 1 Gbps/33 TB | AI Proxy (secondary), Backup, Staging, **Monitoring** |
| gateway | Netcup | Nürnberg DE | 2 GiB | 40 GB | 1 Gbps | **nginx (reverse proxy only)** |
