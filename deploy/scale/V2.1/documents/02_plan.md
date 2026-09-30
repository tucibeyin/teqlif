# teqlif V2.1 — Kurulum Planı

## Faz 0 — Hazırlık (Lokal)

### §0.1 Secrets dosyasını hazırla
- `secrets.env` içinde Bölüm 1 dolu (otomatik üretildi)
- Bölüm 2'yi doldur (LiveKit, Brevo, APNS, Google, Groq, Gemini, Sentry, Telegram, Turnstile, admin)
- node public IP'leri gir: `node1_public_ip`, `node2_public_ip`

### §0.2 Kodu hazırla
- `git pull` son hali al
- Backend V2.1 uyumluluğunu doğrula

---

## Faz 1 — WireGuard Mesh

### §1.1 Her node'da bootstrap çalıştır (paralel)
```bash
SECRETS_FILE=./secrets.env bash bootstrap_node1.sh
SECRETS_FILE=./secrets.env bash bootstrap_node2.sh
# ... diğerleri
```

### §1.2 WireGuard pubkey'leri topla
Her node'da: `cat /etc/wireguard/pubkey`
→ `secrets.env` Bölüm 3'e yaz

### §1.3 Mesh konfigürasyonunu uygula
```bash
bash scripts/wg_mesh_apply.sh
```
Tüm node'lara pubkey'leri dağıtır, WireGuard başlatır.

### §1.4 Mesh doğrula
Her node'dan: `ping 10.10.0.1`

---

## Faz 2 — node1 Core Kurulumu

### §2.1 PostgreSQL 17
- PGDG repo ekle
- `postgresql.conf`: shared_buffers=8GB, work_mem=64MB, max_connections=200, huge_pages=on
- `pg_hba.conf`: lokal + WG subnet erişimi
- DB + kullanıcı oluştur: `createdb teqlif`, `createuser teqlif`
- alembic upgrade head

### §2.2 PgBouncer
- `pgbouncer.ini`: pool_mode=transaction, max_client_conn=1000, default_pool_size=50
- `userlist.txt`: SCRAM hash (finalize scriptinden)

### §2.3 Redis × 3
- redis-core :6379 (uygulama)
- redis-orch :6380 (orchestrator)
- redis-guardian :6382 (guardian)
- Her birinde: `requirepass`, `maxmemory`, `maxmemory-policy allkeys-lru`
- `bind 127.0.0.1 10.10.0.1` (lokal + WG)

### §2.4 MinIO
- Prod bucket'ları oluştur: `teqlif`, `teqlif-dm`
- Versioning aktif
- Lifecycle policy (eski versiyonlar 90 gün sonra sil)

### §2.5 FastAPI + Workers
- `.env.production` doldur
- `systemctl start teqlif teqlif-worker teqlif-worker-critical`

### §2.6 nginx
- SSL: certbot Let's Encrypt (teqlif.com, api.teqlif.com, uploads.teqlif.com)
- Cloudflare origin cert (API proxy)
- Static + media routing

---

## Faz 3 — node2 Backup+Monitoring+ClickHouse

### §3.1 ClickHouse
- Kullanıcı + DB oluştur
- `teqlif.xml` config uygula
- Schema migration

### §3.2 Prometheus
- `prometheus.yml`: tüm node'ları scrape et (WG IP'ler üzerinden)
- Alerting rules

### §3.3 Grafana
- Prometheus + Loki datasource
- Dashboard import

### §3.4 Loki
- `config.yml`: retention 7 gün, `/data/loki` storage

### §3.5 Alertmanager
- Telegram webhook config

### §3.6 Backup scriptleri
- pg_receivewal (WAL stream node1'den)
- pg_dump timer (günlük 01:00 UTC)
- Redis backup timer (günlük 02:00 UTC)
- MinIO backup timer (günlük 03:00 UTC)
- rclone B2 sync timer (günlük 04:00 UTC)

---

## Faz 4 — node3, node4 Streaming

### §4.1 LiveKit Server
- LIVEKIT_VER=v1.7.2
- `livekit.yaml`:
  - `redis.address: 10.10.0.1:6379` (node1 Redis)
  - `keys`: API key/secret
  - `rtc.use_external_ip: true`
  - Port aralığı: 50000-60000/udp

### §4.2 nginx TURN proxy
- UDP 443 → LiveKit TURN

### §4.3 UFW kuralları
- 22/tcp, 51820/udp, 443/tcp+udp, 7880-7881/tcp (WG only), 50000-60000/udp

### §4.4 Doğrula
- node1'den: `curl http://10.10.0.3:7880/` → LiveKit health

---

## Faz 5 — node5 Staging + AI Secondary

### §5.1 Staging stack (tam izole)
- PostgreSQL staging (lokal, port 5433)
- Redis staging (lokal, port 6390)
- MinIO staging (lokal, port 9100)
- LiveKit staging (lokal, port 7890)
- FastAPI staging + workers
- alembic upgrade head (staging DB)

### §5.2 AI Proxy Secondary
- `uvicorn app.ai_proxy.main:app --host 0.0.0.0 --port 8001`
- `.env`: Groq API key, Gemini API key (EU erişim için fallback)
- `AI_PROXY_INTERNAL_TOKEN` doğrula

---

## Faz 6 — node6 AI Primary

### §6.1 AI Proxy Primary
- `uvicorn app.ai_proxy.main:app --host 0.0.0.0 --port 8001`
- `.env`: Groq API key, **Gemini API key** (ABD, kısıtsız erişim)
- `AI_PROXY_INTERNAL_TOKEN` (node5 ile aynı token)

### §6.2 Failover zinciri
- node1 app config: `AI_PROXY_URL=http://10.10.0.6:8001`
- Fallback: `AI_PROXY_FALLBACK_URL=http://10.10.0.5:8001`

---

## Faz 7 — Plug-and-Play Streaming Sistemi

### §7.1 Generic streaming bootstrap
- `bootstrap_streaming.sh <WG_IP> <NODE_NAME>` hazırla
- LiveKit config template (merkezi Redis'e bağlanır)
- WireGuard config template (dinamik peer ekleme)

### §7.2 add_streaming_node.sh
- Yeni node'da bootstrap çalıştır
- Pubkey'i topla
- Tüm node'lara `wg set wg0 peer <pubkey> ...` ile ekle
- Yeni node'a tüm mevcut pubkey'leri gönder

### §7.3 Kapasite izleme
- Prometheus'ta LiveKit participant count alerti
- Eşik: node başına 500 concurrent participant → yeni node öner

---

## Faz 8 — Entegrasyon Testi

### §8.1 API testleri
- `curl https://api.teqlif.com/health`
- Auth flow, media upload, websocket

### §8.2 Streaming testi
- Test room oluştur, node3+4 load balance doğrula

### §8.3 AI proxy testi
- node6 → Gemini çağrısı
- node6 fail → node5 fallback

### §8.4 Backup doğrulama
- pg_receivewal aktif mi? `pg_receivewal` process kontrol
- MinIO backup geldi mi? `ls /data/backups/minio/`

### §8.5 Monitoring doğrulama
- Grafana'da tüm node'lar görünüyor mu?
- Loki'de log akıyor mu?

---

## Plug-and-Play Streaming — Yeni Node Ekleme (Operasyonel)

Kapasite dolduğunda:

```bash
# 1. Yeni VPS kirala, SSH erişimi al
# 2. Lokal makineden:
export NEW_NODE_HOST="<yeni-sunucu-ip>"
export STREAMING_WG_IP="10.10.0.20"   # bir sonraki boş IP
export STREAMING_NODE_NAME="node-stream-3"
export SECRETS_FILE="./secrets.env"

bash deploy/scale/V2.1/scripts/add_streaming_node.sh
# ~5 dakika, otomatik tamamlanır
```
