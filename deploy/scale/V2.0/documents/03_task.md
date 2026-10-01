# V2.0 Görev Takip Listesi

**KURAL (HARD REQUIREMENT):**
Her adım şu sırayla tamamlanmalıdır:
1. **Uygula:** Görevi gerçekleştir.
2. **Commit & Push:** Yapılan değişikliği repoya gönder.
3. **Test Et:** Altında `➔ TEST:` ile belirtilen koşulu çalıştır ve başarılı çıktıyı teyit et.
4. **Damgala:** Görevi `[x]` olarak işaretle ve `[Commit: _______]` alanına commit hash'ini yaz.

**Kaynak:** [02_plan.md](02_plan.md)  
**Son Güncelleme:** 2026-09-29  
**Durum Açıklaması:** `[ ]` = Bekliyor · `[x]` = Tamamlandı · `[-]` = İptal / Geçerli Değil

---

## §0.0 — Secrets Üretimi (Lokalde — Tek Seferlik)

- [ ] `[Commit: _______]` `~/teqlif-secrets.env` oluştur → `chmod 600` → asla repoya ekleme
  ➔ **TEST:** `ls -l` ile dosya izinlerinin doğruluğunu teyit et.
- [ ] `[Commit: _______]` `teqlif_db_password` üret → `openssl rand -hex 32`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `replicator_password` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `core_redis_pass` üret
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `orch_redis_pass` üret
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `guardian_redis_pass` üret
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `teqlif_ch_password` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `secret_key` üret (prod JWT)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `staging_secret_key` üret (staging JWT — prod'dan farklı)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `staging_pg_pass` üret
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `staging_redis_pass` üret
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `minio_staging_root_user` + `minio_staging_root_password` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `livekit_staging_api_key` + `livekit_staging_api_secret` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `minio_root_user` + `minio_root_password` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `ai_proxy_internal_token` üret
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` External servis credential'larını panellerden al: LiveKit, Brevo, Firebase, APNS, Google, Sentry, Telegram, CF Turnstile → dosyaya ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 0 — Kod Hazırlığı (Lokalde)

### 0.1 — `edge_orchestrator.py` Kaldırma

- [ ] `[Commit: _______]` `backend/app/services/edge_orchestrator.py` sil
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Import eden tüm router/servis dosyalarında referansları temizle (~10 dosya)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`'den kaldır: `edge_livekit_urls` (harici), `edge_minio_urls` (harici), `minio_storage_quota_percent`, `edge_metrics_interval_sec`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.2 — Guardian Altyapısı — Redis + Local Agent

#### 0.2.1 — Redis Altyapısı

- [ ] `[Commit: _______]` `config.py`: `orch_redis_url: str`, `guardian_redis_url: str` ekle
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `redis_client.py`: `get_orch_redis()`, `get_guardian_redis()` fonksiyonları ekle
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `backend/app/services/orch_client.py` oluştur — 4 kademeli fallback:
  ➔ **TEST:** `ls -ld /app/services/orch_client.py`` ile dizinin/dosyanın oluştuğunu teyit et.
  - Kademe 1: Orch-redis `orch:routing:*` key'leri
  - Kademe 2: `/var/lib/teqlif/guardian_state.json` taze (≤90s)
  - Kademe 3: Stale guardian_state.json (son bilinen topoloji)
  - Kademe 4: `config.py` hardcoded defaults (node1/node4/node7/node8)
- [ ] `[Commit: _______]` `get_stream_node()`, `get_storage_nodes()`, `get_ai_proxy_url()` — 4 kademeli zinciri kullanır
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Fallback seviyesi Prometheus metric olarak yayınla: `orch_client_fallback_level{level="redis|json_fresh|json_stale|config"}`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

#### 0.2.2 — Guardian Agent — `backend/scripts/guardian_agent.py`

- [ ] `[Commit: _______]` `edge_metrics_agent.py`'ı sil
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `guardian_agent.py` oluştur — iki bağımsız goroutine:
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
  - **A) Local Agent (her 3s):**
    - `node.conf` okuma (YAML) → node_id, env, guardian_priority, components, network, hardware
    - psutil metrik toplama: cpu_percent, load_1m/5m/15m, ram_used_percent, swap_used_gb, disk_*, net_out_mbps, net_in_mbps, tcp_connections
    - Component health check: `type: http` → httpx GET timeout=2s; `type: cmd` → subprocess(shell=True, env=os.environ) timeout=3s
    - Rol özel telemetri: stream (livekit_active_rooms, stream_score), storage (minio_health, minio_io), gateway (nginx_active_connections, nginx_rps), core (pg_replication_lag_sec)
    - Orch-redis'e yaz: `HSET edge:metrics:{node_id}` EXPIRE 6, `HSET edge:health:{node_id}` EXPIRE 6, `HSET edge:telemetry:{node_id}` EXPIRE 10
    - `guardian_state.json` okuma → lokal routing önbelleği
    - Local healer: health=="failed" + restart count > threshold → `systemctl reset-failed + start`, `guardian:events`'e yaz
  - **B) Heartbeat + Election (her 5s UDP 9901):**
    - UDP broadcast → tüm WG peer'larına heartbeat gönder
    - Peer tablosunu tut
    - Adım 1: `SET guardian:leader EX 15 NX` → başarılı ise lider, başarısız ise takip et; `EXPIRE guardian:leader 15` (TTL yenile)
    - Redis kopma backoff: `redis_unavailable_since` takibi; 20s geçmeden Adım 2'ye geçme
    - Adım 2 (Redis 20s+ kapalı): UDP priority karşılaştırma; lider → sadece Telegram CRITICAL alert, coordinator_loop başlatma (V2.0 sınırı)
- [ ] `[Commit: _______]` `ALLOWED_COMMANDS`: systemctl çağrıları → `subprocess(["sudo","systemctl",...])` (direkt çağrı Permission Denied)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` HTTP server background thread → Prometheus `/metrics` endpoint `:9200`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `guardian_state.json` atomic write: temp file → rename
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.3 — Storage Service + LiveKit Reconnect Fix

#### 0.3.1 — LiveKit Reconnect

- [ ] `[Commit: _______]` `routers/streams.py`: reconnect endpoint `stream.livekit_url` → `orch_client.get_stream_node()` ile değiştir (DB fallback olarak tut)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `routers/calls.py`: `allocate_node()` → `orch_client.get_stream_node()`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `worker.py`: `allocate_node()` çağrıları → `orch_client.get_stream_node()`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `tasks/video_tasks.py`: `allocate_node()` → `orch_client.get_stream_node()`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `routers/webhooks.py`: stream node referansları → `orch_client`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

#### 0.3.2 — Storage Service — Dual-Write + URL Şeması

- [ ] `[Commit: _______]` `_build_public_url()`: node_id kaldır → `settings.media_host/{bucket}/{key}` döndür
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `upload_bytes()`: `asyncio.gather` ile tüm storage node'larına paralel PUT; min 1 başarılı → yükleme başarılı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `upload_file_dm()`: aynı dual-write mantığı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `delete_object()`: `storage_node_id` DB kolonunu okur, sadece o node'dan sil
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Alembic migration: `storage_node_id` kolonu
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `scripts/cleanup_orphaned_storage.py` ARQ job: MinIO objelerini DB ile karşılaştır, 24h grace period zorunlu, yetim dosyaları her iki node'dan sil
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

#### 0.3.3 — Upload Mimarisi — Presigned PUT (Gateway Bypass)

- [ ] `[Commit: _______]` `POST /api/upload/presign` endpoint: JWT doğrula → kota kontrol → `pending_uploads` kaydı → MinIO presigned PUT URL üret → URL'i `UPLOADS_HOST`'a rewrite et → `{upload_id, put_url, key, expires_in: 900}` döndür
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `PUT uploads.teqlif.com/{key}`: MinIO imzayı doğrular → S3'e yazar (gateway yok)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `POST /api/upload/complete` endpoint: pending_uploads durumu `completed`'a güncelle → ARQ `process_media_upload` tetikle → `{url: media.teqlif.com/...}` döndür
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `worker.py`: `process_media_upload` ARQ task ekle (FFmpeg + Pillow + WS notify)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Alembic migration: `pending_uploads` tablosu (`upload_id UUID PK`, `user_id FK`, `key TEXT`, `context TEXT`, `status TEXT`, `expires_at TIMESTAMP`)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Mobile: 403 Expired URL transparent retry: PUT 403 → sessiz `/presign` yeniden → PUT tekrar (tek retry)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `routers/streams.py`: stream thumbnail upload → presign/complete
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Tüm `UploadFile` endpoint'leri kaldır (V2.0 yeşil alan — legacy upload yok)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.4 — Config Temizliği

- [ ] `[Commit: _______]` `config.py`: `site_url` hardcoded default kaldır
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `use_pgbouncer: bool = True` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `media_host`, `uploads_host` ekle (default yok — .env'de zorunlu)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `minio_endpoint: str = "http://10.10.0.8:9000"` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `minio_endpoint_dm: str = "http://10.10.0.8:9000"` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `ai_proxy_url: str` ekle — default `http://10.10.0.3:8001`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `edge_livekit_urls` default → `["http://10.10.0.1:7880", "http://10.10.0.6:7880"]` (4. kademe fallback)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `edge_minio_urls` default → `["http://10.10.0.8:9000", "http://10.10.0.12:9000"]` (4. kademe fallback)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `upload_presign_ttl: int = 900` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `config.py`: `clickhouse_db` default `"default"` → `"teqlif_prod_analytics"`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.5 — Node Template Dosyaları

- [ ] `[Commit: _______]` Tüm 11 node için `resources/.env.{production,staging}.template` dosyalarını `<placeholder>` değerleriyle repoya commit et
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
  - gateway1, gateway2, node1, node2, node4, node5, node6, node7, node8, node9 → `.env.production.template`
  - node3 → `.env.staging.template`

### 0.6 — Guardian Koordinatör — `backend/app/guardian/`

- [ ] `[Commit: _______]` `backend/app/guardian/` modülü oluştur
  ➔ **TEST:** `ls -ld /app/guardian/`` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` `topology.py`: guardian topology, components, roles, env set'lerini orch-redis'e yaz
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `service_state.py`: HEALTHY / DEGRADED / DOWN state makinesi; `alive_nodes` listesi; `degraded_since` takibi
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `job_state.py`: Job state machine — PENDING → RUNNING → INTERRUPTED / SUCCESS / FAILED / DEAD; checkpoint + resume
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `playbook.py`: Playbook sistemi — failover_storage, failover_ai, failover_gateway, failover_core, stream_rebalance, service_heal, storage_rebalance
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `routing.py`: `is_routing_eligible()` — 4 şart: traffic_eligible=true + env eşleşme + systemd active + health OK
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `coordinator.py`: Lider seçilince coordinator_loop başlat; topology değişikliğinde playbook tetikle; Prometheus /metrics endpoint
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `election.py`: Redis NX lider seçimi + UDP fallback (V2.0: basit priority karşılaştırma); Redis backoff 20s guard; election.mode=="udp" guard (coordinator_loop başlatma)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `guardian_state.json`: `/var/lib/teqlif/guardian_state.json` — routing kararları, node sağlıkları, son güncelleme zamanı; atomic write (temp → rename)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.7 — Ops Komutları

- [ ] `[Commit: _______]` `scripts/teqlif-restart.sh`: WG IP → rol tespiti → uygun servisleri yeniden başlat (node8=10.10.0.12=storage dahil)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `scripts/teqlif-refresh.sh`: git pull + sync (veri servislerine dokunmaz)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `deploy/scale/V2.0/node.conf.example`: tüm roller için örnek şablon
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.8 — Güvenlik Düzeltmesi

- [ ] `[Commit: _______]` FastAPI `--forwarded-allow-ips 10.10.0.2,10.10.0.9` (gateway1 + gateway2 WG IP'leri)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.9 — Doğrulama (Lokalde)

- [ ] `[Commit: _______]` `python -c "from app.config import settings; print(settings.model_fields.keys())"`
  ➔ **TEST:** Çalıştırıldı ve hata dönmediği teyit edildi.
- [ ] `[Commit: _______]` `grep -r "edge_orchestrator" backend/app/`
  ➔ **TEST:** Çalıştırıldı ve 0 sonuç döndüğü teyit edildi.
- [ ] `[Commit: _______]` `grep -r "minio_storage_quota" backend/app/`
  ➔ **TEST:** Çalıştırıldı ve 0 sonuç döndüğü teyit edildi.
- [ ] `[Commit: _______]` `dart analyze mobile/`
  ➔ **TEST:** 0 hata alındığı teyit edildi.

### 0.10 — Cloudflare Güvenlik Yapılandırması (Free Tier — Dashboard)

- [ ] `[Commit: _______]` SSL/TLS Mode → **Full (Strict)**
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` HSTS → Enable (max-age 6 months, includeSubDomains)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Minimum TLS Version → TLS 1.2
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Security Level → **Low** (Medium/High Flutter dart:io'yu bloklar)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Bot Fight Mode → **Devre Dışı** (non-browser UA challenge → native app trafiği bloklanır)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Browser Integrity Check → **Devre Dışı** (native app Referer taşımaz)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` IP Access Rules: Tor → Block; bilinen scanner ASN'leri → Block
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` WAF Custom Rules 5 kural: Path Traversal+SQLi (Block), kötü UA (Block), auth endpoint tehdit skoru (Managed Challenge), upload flood (JS Challenge), header anomalisi (Managed Challenge)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Cache Rules: `media.teqlif.com/*` → Cache Everything + 1 month; `uploads.teqlif.com/*` → Bypass; `api.teqlif.com/api/*` → Bypass; `*.min.js` → Cache Everything + 1 year
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 0.11 — Mobil Kod Değişiklikleri

- [ ] `[Commit: _______]` `image_cache_manager.dart`: `stalePeriod` → `Duration(days: 14)`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `video_cache_manager.dart`: `getTemporaryDirectory()` → `getApplicationSupportDirectory()`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Logout akışı: `CacheService.clearData()` + `VideoCacheManager.instance.updateCache({}, {})` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `app_config.dart`: `mediaBaseUrl` türetme kaldır; `uploadsHost`, `mediaHost`, `shareBaseUrl`, `captchaBaseUrl` → `String.fromEnvironment(...)` ile oku
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `captcha_service.dart`: hardcoded `'https://www.teqlif.com'` → `appConfig.captchaBaseUrl`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` 14 hardcoded share URL noktasını → `appConfig.shareBaseUrl` ile değiştir
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `dart_defines/staging.json` + `release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` ekle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Backend: `MessageOut.cache_key: Optional[str]` ekle; `_presign_if_dm()` hem `url` hem `cache_key` döndürsün
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Mobile: `CachedNetworkImage(imageUrl: signedUrl, cacheKey: msg.mediaCacheKey)` — `cacheKey` zorunlu (eksik = her 15dk yeniden indirme)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `frontend/.well-known/assetlinks.json` oluştur (Android App Links)
  ➔ **TEST:** `ls -ld /.well-known/assetlinks.json`` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` `frontend/.well-known/apple-app-site-association` oluştur (iOS Universal Links, Content-Type: application/json)
  ➔ **TEST:** `ls -ld /.well-known/apple-app-site-association`` ile dizinin/dosyanın oluştuğunu teyit et.

---

## Faz 1 — OS Temeli (Tüm Node'lar)

### 1.1 — Temel Paketler (Her Node)

- [ ] `[Commit: _______]` `apt-get update && upgrade -y`
  ➔ **TEST:** `dpkg -l | grep <paket_adi>` ile paketlerin yüklendiğini teyit et.
- [ ] `[Commit: _______]` Paketler: curl, git, ufw, fail2ban, wireguard, chrony, htop, iotop, nethogs, unattended-upgrades, rsync, logrotate, jq, python3, python3-pip, python3-venv, python3-dev, build-essential, auditd
  ➔ **TEST:** `dpkg -l | grep <paket_adi>` ile paketlerin yüklendiğini teyit et.

### 1.2 — Kullanıcı ve SSH (Her Node)

- [ ] `[Commit: _______]` `adduser tucibeyin` + `usermod -aG sudo`
  ➔ **TEST:** `id tucibeyin` komutunun çalıştığını teyit et.
- [ ] `[Commit: _______]` SSH public key → `/home/tucibeyin/.ssh/authorized_keys`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `sshd_config`: PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl restart ssh`
  ➔ **TEST:** `ssh -o PasswordAuthentication=no root@<ip>` ile root girişinin reddedildiği görüldü.

### 1.3 — Dizin Yapısı (Her Node)

- [ ] `[Commit: _______]` `/var/www/teqlif.com`, `/etc/teqlif` (chmod 700), `/var/log/teqlif/{api,worker,orchestrator}` oluştur
  ➔ **TEST:** `ls -l` ile dosya izinlerinin doğruluğunu teyit et.
- [ ] `[Commit: _______]` `chown tucibeyin:tucibeyin` tüm dizinlere
  ➔ **TEST:** `ls -ld <dizin>` ile sahipliğin tucibeyin:tucibeyin olduğunu teyit et.

### 1.4 — /etc/teqlif/node.conf (Her Node)

- [ ] `[Commit: _______]` Her node için YAML `node.conf` oluştur: `node_id`, `env`, `guardian_priority`, `network` (wg_ip, speed_mbps), `hardware` (cpu_cores, ram_gb), `components[]` (name, env, role, traffic_eligible, traffic_type, health_check)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `chmod 644 /etc/teqlif/node.conf`
  ➔ **TEST:** `stat -c '%a' /etc/teqlif/node.conf`` ile izinleri teyit et.

### 1.5 — fail2ban (Her Node)

- [ ] `[Commit: _______]` fail2ban kur + `sshd` jail aktif et
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `maxretry = 5`, `bantime = 3600`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 1.6 — NTP + Timezone (Her Node)

- [ ] `[Commit: _______]` chrony yapılandır → `systemctl enable --now chrony`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.
- [ ] `[Commit: _______]` `timedatectl set-timezone UTC`
  ➔ **TEST:** `chronyc tracking | grep "System time"` çıktısında senkronizasyon doğrulandı.

### 1.7 — Otomatik Güvenlik Güncellemeleri (Her Node)

- [ ] `[Commit: _______]` `unattended-upgrades` aktif et
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Yalnızca güvenlik güncellemeleri → `50unattended-upgrades` yapılandır
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 1.8 — LimitNOFILE — Sistem Geneli (Her Node)

- [ ] `[Commit: _______]` `/etc/security/limits.conf`: `* soft nofile 65536` + `* hard nofile 65536`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/sysctl.d/99-teqlif.conf`: `fs.file-max = 2097152`
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.

### 1.9 — Swap Dosyası (Core + Storage Node'ları)

- [ ] `[Commit: _______]` node5, node6: 8 GB swapfile oluştur → `mkswap` → `swapon` → `/etc/fstab`'a ekle
  ➔ **TEST:** `ls -ld /etc/fstab`'a` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` node7, node8: 2 GB swapfile
  ➔ **TEST:** `free -h | grep Swap` çıktısında Swap alanının aktif olduğu görüldü.

### 1.10 — Log Rotation ve Sınırlandırma (Her Node)

- [ ] `[Commit: _______]` `/etc/logrotate.d/teqlif` → `/var/log/teqlif/*.log` weekly, rotate 4, compress, missingok
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/systemd/journald.conf` → `SystemMaxUse=300M` yap, `systemctl restart systemd-journald`
  ➔ **TEST:** `cat /etc/systemd/journald.conf | grep SystemMaxUse=300M` çıktısı alındı.

### 1.11 — Audit Logging — auditd (Her Node)

- [ ] `[Commit: _______]` `resources/security/audit.rules` → `/etc/audit/rules.d/teqlif.rules`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now auditd`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.

### 1.12 — Transparent Hugepages Kapatma (Her Node)

- [ ] `[Commit: _______]` `resources/systemd/thp-disable.service` → `/etc/systemd/system/`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now thp-disable`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.

### 1.13 — Doğrulama (Her Node)

- [ ] `[Commit: _______]` `ssh -o PasswordAuthentication=no tucibeyin@<ip>` → root girişi reddedilmeli
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `chronyc tracking | grep "System time"` → senkron
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `free -h | grep Swap` → swap aktif (core/storage node'ları)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 2 — WireGuard Mesh (Tüm Node'lar)

### 2.1 — Anahtar Üretimi (Her Node'da VPS'te)

- [ ] `[Commit: _______]` `wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/pubkey`
  ➔ **TEST:** `cat /etc/wireguard/privatekey` vb. ile anahtarın oluştuğunu teyit et.
- [ ] `[Commit: _______]` `chmod 600 /etc/wireguard/privatekey`
  ➔ **TEST:** `stat -c '%a' /etc/wireguard/privatekey`` ile izinleri teyit et.
- [ ] `[Commit: _______]` Pubkey'i `~/teqlif-secrets.env`'e not et (tüm 11 node)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 2.2 — wg0.conf Yapısı (Her Node)

- [ ] `[Commit: _______]` Her node için `wg0.conf` oluştur: `[Interface]` Address + ListenPort + MTU=1420 + PrivateKey
  ➔ **TEST:** `cat /etc/wireguard/privatekey` vb. ile anahtarın oluştuğunu teyit et.
- [ ] `[Commit: _______]` Tüm peer'ları `[Peer]` blokları olarak ekle (`PersistentKeepalive = 25` zorunlu)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Non-core node'larda node5 peer'ına VIP'leri ekle: `10.10.0.10/32, 10.10.0.11/32`
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `chmod 600 /etc/wireguard/wg0.conf`
  ➔ **TEST:** `stat -c '%a' /etc/wireguard/wg0.conf`` ile izinleri teyit et.

### 2.3 — Başlatma (Her Node)

- [ ] `[Commit: _______]` `wg-quick up wg0`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable wg-quick@wg0`
  ➔ **TEST:** `systemctl is-enabled wg-quick@wg0` çıktısının enabled olduğunu teyit et.

### 2.4 — Mesh Doğrulama

- [ ] `[Commit: _______]` WG IP'lerine Ping at
  ➔ **TEST:** Her node'dan diğer 10 node'a `ping -c1 10.10.0.x` atıldı, %0 packet loss.
- [ ] `[Commit: _______]` `wg show wg0`
  ➔ **TEST:** Her peer'da Latest handshake < 5 dakika olduğu teyit edildi.

### 2.5 — Failover Sudoers — Non-Core Node'lar

- [ ] `[Commit: _______]` `/etc/sudoers.d/wg-failover` → `tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *` + `wg-quick save wg0`
  ➔ **TEST:** `sudo -l -U tucibeyin` komutunun NOPASSWD izinlerini yansıttığını teyit et.

### 2.6 — Guardian Sudoers — Tüm Node'lar

- [ ] `[Commit: _______]` `/etc/sudoers.d/guardian-systemctl` → `teqlif*` start/stop/restart/reload/reset-failed NOPASSWD
  ➔ **TEST:** `sudo -l -U tucibeyin` komutunun NOPASSWD izinlerini yansıttığını teyit et.
- [ ] `[Commit: _______]` Per-node ek servisler: pgbouncer, redis-core/orch/guardian, livekit, minio, nginx, prometheus, clickhouse-server, redis-staging, minio-staging, livekit-staging (ilgili node'lara)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

---

## Faz 3 — Rol Bazlı OS Tuning (Tüm Node'lar)

### 3.1 — Gateway (gateway1, gateway2)

- [ ] `[Commit: _______]` `/etc/sysctl.d/99-teqlif.conf`: `net.core.somaxconn=65535`, `net.ipv4.tcp_max_syn_backlog=65535`, `net.ipv4.tcp_tw_reuse=1`, `net.core.netdev_max_backlog=5000`
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.
- [ ] `[Commit: _______]` UFW: varsayılan deny; 22/tcp; 51820/udp; WG subnet (wg0); UDP 9901 (guardian); 80/tcp + 443/tcp yalnızca Cloudflare IP aralıklarından (17 CIDR)
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.

### 3.2 — Core (node5, node6)

- [ ] `[Commit: _______]` `/etc/sysctl.d/99-teqlif.conf`: `vm.swappiness=10`, `vm.dirty_ratio=15`, `vm.dirty_background_ratio=5`, `net.core.somaxconn=65535`, `net.ipv4.tcp_tw_reuse=1`, `kernel.shmmax` (RAM'in %75'i)
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.
- [ ] `[Commit: _______]` UFW: WG-only (22/tcp + 51820/udp + wg0 subnet + UDP 9901)
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.

### 3.3 — Stream (node1, node4)

- [ ] `[Commit: _______]` `/etc/sysctl.d/99-teqlif.conf`: `net.core.rmem_max=8388608`, `net.core.wmem_max=8388608`, `net.ipv4.udp_mem`, `net.core.netdev_max_backlog=5000`
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.
- [ ] `[Commit: _______]` UFW: 22/tcp, 51820/udp, wg0, UDP 9901; LiveKit: 7880/tcp, 7881/tcp, 7882/udp, 3478/udp, 5349/tcp, 50000:60000/udp
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.

### 3.4 — Storage (node7, node8)

- [ ] `[Commit: _______]` `/etc/sysctl.d/99-teqlif.conf`: `vm.dirty_ratio=40`, `vm.dirty_background_ratio=10`, `net.core.rmem_max=4194304`, `net.core.wmem_max=4194304`
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.
- [ ] `[Commit: _______]` UFW: 22/tcp, 51820/udp, wg0, UDP 9901; 80/tcp + 443/tcp (tümü — DNS Only, CF yok); MinIO 9000/tcp ufw deny
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.
- [ ] `[Commit: _______]` HDD udev: mq-deadline scheduler + 2048 KB readahead + nr_requests=128 (sd[a-z] rotational==1)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` iptables hashlimit: 80/443 → 60/min burst 80 DROP + netfilter-persistent save
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 3.5 — AI Proxy (node2) + Monitor (node9)

- [ ] `[Commit: _______]` node2 UFW: WG-only (22/tcp + 51820/udp + wg0 + UDP 9901)
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.
- [ ] `[Commit: _______]` node9 UFW: WG-only; `ufw allow in on wg0 proto udp to any port 9901`; Grafana 3000/tcp → WG-only
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.
- [ ] `[Commit: _______]` node9 sysctl: `vm.overcommit_memory=1` (Prometheus + Loki mmap)
  ➔ **TEST:** `sysctl -a | grep <parametre>` ile çekirdek değerlerinin atandığını teyit et.

### 3.6 — Sysctl Uygulama (Her Node)

- [ ] `[Commit: _______]` `sysctl -p /etc/sysctl.d/99-teqlif.conf`
  ➔ **TEST:** Çalıştırıldı, kernel hata vermedi.
- [ ] `[Commit: _______]` `ufw status verbose`
  ➔ **TEST:** Dışarıdan gelen gereksiz portların kapalı, yalnızca Cloudflare ve wg0 subneti izinli olduğu görüldü.

---

## Faz 4 — Veri Katmanı HA (node5 Primary + node6 Standby)

### 4.1 — PostgreSQL 17 — node5 Primary

- [ ] `[Commit: _______]` PGDG repo ekle → `postgresql-17` kur
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `postgresql.conf`: `max_connections=200`, `shared_buffers=2GB`, `work_mem=20MB`, `maintenance_work_mem=512MB`, `wal_level=replica`, `max_wal_senders=5`, `max_replication_slots=3`, `synchronous_commit=off`, `random_page_cost=1.1`, `effective_io_concurrency=200`, `max_slot_wal_keep_size=5GB`
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `pg_hba.conf`: replication kuralı → `host replication replicator 10.10.0.7/32 scram-sha-256`; wal_backup_node9 → `host replication replicator 10.10.0.13/32 scram-sha-256`; PgBouncer loopback → `host teqlif teqlif 127.0.0.1/32 scram-sha-256`
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `teqlif` DB + `teqlif` user oluştur; `replicator` user oluştur
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Replication slot: `SELECT pg_create_physical_replication_slot('node6_slot')` + `SELECT pg_create_physical_replication_slot('wal_backup_node9')`
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` postgres-exporter servis kur + enable
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.

### 4.2 — PgBouncer — node5 ve node6

- [ ] `[Commit: _______]` `pgbouncer.ini`: `host=127.0.0.1`, `pool_mode=transaction`, `max_client_conn=2000`, `default_pool_size=25`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `pgbouncer.service.d/restart.conf` → `Restart=always`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable pgbouncer`
  ➔ **TEST:** `systemctl is-enabled pgbouncer` çıktısının enabled olduğunu teyit et.

### 4.3 — Core Redis — node5 (port 6379)

- [ ] `[Commit: _______]` `redis-core.conf`: port 6379, requirepass, `maxmemory-policy volatile-lru`, `appendonly no`, `save 3600 1`, RuntimeDirectory=redis-core
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `redis-core.service` → `/etc/systemd/system/`; `systemctl disable --now redis-server`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `systemctl enable redis-core`
  ➔ **TEST:** `systemctl is-enabled redis-core` çıktısının enabled olduğunu teyit et.

### 4.4 — Orch Redis — node5 (port 6380)

- [ ] `[Commit: _______]` `redis-orch.conf`: port 6380, requirepass, `appendonly no`, dir=/var/lib/redis-orch
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `redis-orch.service` → `/etc/systemd/system/`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `systemctl enable redis-orch`
  ➔ **TEST:** `systemctl is-enabled redis-orch` çıktısının enabled olduğunu teyit et.

### 4.4.1 — Guardian Redis — node5 (port 6382)

- [ ] `[Commit: _______]` `redis-guardian.conf`: port 6382, requirepass, `appendonly yes` (job checkpoint kalıcı), dir=/var/lib/redis-guardian, `save 3600 1`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `redis-guardian.service` → `/etc/systemd/system/`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `systemctl enable redis-guardian`
  ➔ **TEST:** `systemctl is-enabled redis-guardian` çıktısının enabled olduğunu teyit et.

### 4.5 — Keepalived — node5 (MASTER)

- [ ] `[Commit: _______]` `keepalived.conf`: `state MASTER`, priority 100, `virtual_ipaddress 10.10.0.10/24 dev wg0` + `10.10.0.11/24 dev wg0`, `nopreempt`
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `vrrp_script chk_redis`: `redis-cli -a $pass --no-auth-warning ping` → OK/FAILED
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `notify_master /etc/keepalived/scripts/wg_vip_node5.sh`
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `notify_backup /etc/keepalived/scripts/wg_vip_failover.sh`
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `wg_vip_node5.sh`: VIP'leri `wg set` ile tüm non-core node'ların routing tablosuna yaz (parallel SSH + wait)
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `wg_vip_failover.sh`: MASTER bloğu (node9 Quorum ping + node5 SSH split-brain guard, PG promote pg_is_in_recovery check, PgBouncer enable, WG routing güncelle SSH loop parallel); BACKUP bloğu (PgBouncer disable, REPLICAOF node5 IP)
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` SSH public key → tüm peer node'ların `authorized_keys`'ine ekle (node1/2/3/4/7/8/9 + gateway1/2)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable keepalived`
  ➔ **TEST:** `systemctl is-enabled keepalived` çıktısının enabled olduğunu teyit et.

### 4.6 — PostgreSQL Streaming Replication — node6

- [ ] `[Commit: _______]` node5 hazırken: `pg_basebackup -h 10.10.0.5 -U replicator -D /var/lib/postgresql/17/main -P -R --slot=node6_slot`
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `postgresql.conf` override: `random_page_cost=4.0`, `effective_io_concurrency=8` (node6 yavaş disk)
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `standby.signal` mevcut → `systemctl start postgresql` (node6)
  ➔ **TEST:** `systemctl status postgresql` komutuyla active (running) olduğunu teyit et.
- [ ] `[Commit: _______]` `select * from pg_stat_replication` → node6 bağlı + replay_lag ~0
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.

### 4.7 — Redis Replication — node6

- [ ] `[Commit: _______]` redis-core/orch/guardian conf: `REPLICAOF 10.10.0.11 6379/6380` (VIP üzerinden); redis-guardian: `REPLICAOF 10.10.0.5 6382` (direkt IP — VIP yok)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `systemctl enable redis-core redis-orch redis-guardian` (node6)
  ➔ **TEST:** `systemctl is-enabled redis-core` çıktısının enabled olduğunu teyit et.

### 4.9 — Faz 4 Doğrulama

- [ ] `[Commit: _______]` `psql -h 127.0.0.1 -U teqlif -d teqlif`
  ➔ **TEST:** Başarıyla bağlandı.
- [ ] `[Commit: _______]` `select * from pg_stat_replication`
  ➔ **TEST:** `node6_slot` ve lag ~0 görüldü.
- [ ] `[Commit: _______]` `redis-cli -h 10.10.0.11 -p 6379 -a <pass> info replication`
  ➔ **TEST:** `role:master` ve `connected_slaves:1` görüldü.
- [ ] `[Commit: _______]` `systemctl is-active keepalived` → active (node5 + node6)
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` VIP doğrula
  ➔ **TEST:** Node5'te `ip addr show wg0` çıktısında `10.10.0.10` ve `10.10.0.11` sanal IP'leri görülüyor.
- [ ] `[Commit: _______]` PgBouncer bağlantısı
  ➔ **TEST:** `psql -h 127.0.0.1 -p 6432 -U teqlif` başarıyla bağlandı.

---

## Faz 5 — Core App (node5 Primary + node6 Standby)

### 5.1 — Repo ve Python Ortamı — node5

- [ ] `[Commit: _______]` `git clone` → `/var/www/teqlif.com`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `python3 -m venv /var/www/teqlif.com/.venv`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `.venv/bin/pip install -r backend/requirements.txt`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.1.1 — Alembic — DB Şema Kurulumu

- [ ] `[Commit: _______]` `cd backend && .venv/bin/python -m alembic upgrade head`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Migration başarılı → tüm tablolar mevcut
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.2 — .env.production — node5

- [ ] `[Commit: _______]` Template'den `/etc/teqlif/.env.production` oluştur
  ➔ **TEST:** `ls -ld /etc/teqlif/.env.production`` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` Tüm `<placeholder>`'ları gerçek değerlerle doldur
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `chmod 600 /etc/teqlif/.env.production`
  ➔ **TEST:** `stat -c '%a' /etc/teqlif/.env.production`` ile izinleri teyit et.

### 5.3 — Systemd Servisleri — node5

- [ ] `[Commit: _______]` `teqlif.service` → enable (MemoryMax=1500M, --workers 4, --forwarded-allow-ips)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-worker.service` → enable (MemoryMax=1000M)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-worker-critical.service` → enable (MemoryMax=800M)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable (MemoryMax=300M)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian`
  ➔ **TEST:** `systemctl status teqlif` komutuyla active (running) olduğunu teyit et.

### 5.3.1 — teqlif-ai-proxy — node5 (Son Çare Fallback)

- [ ] `[Commit: _______]` `teqlif-ai-proxy.service` → enable ama **başlatma** (orchestrator tetikler, MemoryMax=600M)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.4 — Ops Komutları Kurulumu

- [ ] `[Commit: _______]` `teqlif-restart.sh` → `/usr/local/sbin/teqlif-restart` (executable)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-refresh.sh` → `/usr/local/sbin/teqlif-refresh`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.5 — node6 Standby App Kurulumu

- [ ] `[Commit: _______]` `git clone` → `/var/www/teqlif.com` (node6)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `.venv` + pip install
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/teqlif/.env.production` (node6 — aynı template, aynı değerler)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Tüm teqlif servisler **enable ama başlatma** (failover'da Keepalived tetikler)
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` teqlif-guardian → enable + start (node6'da da heartbeat çalışmalı)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.6 — Failover Testi

- [ ] `[Commit: _______]` Failover Testi (Uygulama)
  ➔ **TEST:** Node5 Keepalived durdurulduğunda Node6'nın VIP'leri devraldığı ve API'nin çalışmaya devam ettiği doğrulandı.
- [ ] `[Commit: _______]` `ip addr show wg0` (node6) → VIP'ler görünmeli
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` API çağrısı → gateway → node6'ya ulaşıyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node5 geri getir → failback (nopreempt — otomatik değil, manüel)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.6.1 — Failback Prosedürü

- [ ] `[Commit: _______]` node6: `systemctl stop teqlif teqlif-worker teqlif-worker-critical`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Replication sync doğrula: `pg_stat_replication` lag ~0
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` node5 Keepalived → MASTER alır → VIP node5'e geçer
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` node5 servisleri start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 5.7 — Faz 5 Doğrulama

- [ ] `[Commit: _______]` API Health Check
  ➔ **TEST:** `curl http://127.0.0.1:8000/v1/ping` -> `200 OK` (node5).
- [ ] `[Commit: _______]` ARQ worker çalışıyor
  ➔ **TEST:** `redis-cli -h 10.10.0.11 -p 6379 -a <pass> llen arq:queue:default` yanıt verdi.
- [ ] `[Commit: _______]` Guardian Redis Entegrasyonu
  ➔ **TEST:** `redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"` node5'i listeledi.

---

## Faz 6 — Storage (node7 + node8)

*Faz 5 bittikten sonra Faz 7 ve Faz 8 ile paralel yürütülebilir.*

### 6.1 — HDD Formatı ve Mount (Her İki Node)

- [ ] `[Commit: _______]` HDD diskini formatla: `mkfs.ext4 /dev/sdX`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/fstab`'a ekle → `/data` mount noktası
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `mount -a` → `df -h /data` doğrula
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.2 — MinIO Kurulumu (node7 + node8)

- [ ] `[Commit: _______]` MinIO binary'yi GitHub releases'den indir → `/usr/local/bin/minio`; `mc` client → `/usr/local/bin/mc`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` MinIO data dir: `/data/minio` (HDD) oluştur → `chown tucibeyin`
  ➔ **TEST:** `ls -ld /data/minio`` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` `/etc/teqlif/.env.production` → `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.3 — node7 — MinIO Servisi

- [ ] `[Commit: _______]` `minio.service` → `/etc/systemd/system/`; `MINIO_SERVER_URL=https://uploads.teqlif.com` (presigned imza için zorunlu)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now minio`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.
- [ ] `[Commit: _______]` mc alias kur: `mc alias set minio7 http://127.0.0.1:9000 ...`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Bucket oluştur: `mc mb minio7/teqlif` + `mc mb minio7/teqlif-dm`
  ➔ **TEST:** `ls -ld /teqlif`` ile dizinin/dosyanın oluştuğunu teyit et.
- [ ] `[Commit: _______]` Versioning aktif: `mc version enable minio7/teqlif` + `mc version enable minio7/teqlif-dm`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` ILM: 90 gün versiyonları sakla → `mc ilm add --expire-delete-marker --expire-days 90`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.4 — node7 — nginx (S3 Proxy)

- [ ] `[Commit: _______]` nginx kur + `/var/cache/nginx/storage` (1 GB SSD cache)
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` İki server block:
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
  - `media.teqlif.com` (CF Proxied): set_real_ip_from CF IP ranges; GET/HEAD only; `proxy_cache storage_cache` 7 gün; `Cache-Control: public max-age=31536000 immutable`; rate limit 100r/s burst=200
  - `uploads.teqlif.com` (DNS Only): `limit_conn 10`; 10r/s burst=20; `proxy_cache off`; `Cache-Control: no-store`
- [ ] `[Commit: _______]` upstream: `upstream minio_media` + `upstream minio_uploads` → `proxy_next_upstream` ile fallback
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` CF Origin cert: `/etc/ssl/teqlif/cf-origin.crt` + `.key`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `nginx.service.d/restart.conf` → `Restart=always`
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now nginx`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.

### 6.5 — node8 — MinIO Servisi

- [ ] `[Commit: _______]` node7 ile aynı kurulum → `minio.service`, mc alias, bucket (versioning kur)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` **NOT:** Bucket içeriği boş başlar — Site Replication node7'yi kaynak alır
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.6 — node8 — nginx (S3 Proxy + 404 Fallback)

- [ ] `[Commit: _______]` node7 ile aynı nginx config (upstream node8 MinIO IP'si)
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.

### 6.7 — Guardian — node7 + node8

- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable + start (her iki node)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `edge:metrics:node7` + `edge:metrics:node8` → orch-redis'te mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 6.8 — Cloudflare DNS — Storage

- [ ] `[Commit: _______]` `media.teqlif.com` → node7 IP + node8 IP (iki A record, CF Proxied)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `uploads.teqlif.com` → node7 IP + node8 IP (DNS Only — CF bypass)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.9 — MinIO Site Replication

- [ ] `[Commit: _______]` Her iki MinIO hazır → `mc admin replicate add minio7 minio8`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `mc admin replicate info minio7` → replication aktif
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-storage-cleanup.service` + `teqlif-storage-cleanup.timer` (aylık, node5'te) → enable
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 6.10 — Faz 6 Doğrulama

- [ ] `[Commit: _______]` MinIO Erişim
  ➔ **TEST:** `mc ls minio7/teqlif` komutu hata vermeden çalıştı.
- [ ] `[Commit: _______]` S3 Proxy Health
  ➔ **TEST:** `curl -s https://media.teqlif.com/health` -> Nginx yanıt verdi (200).
- [ ] `[Commit: _______]` Active-Active Replication (Site Sync)
  ➔ **TEST:** Bir dosya yüklendiğinde, her iki node'da da `mc ls` ile eşzamanlı görülebildi.
- [ ] `[Commit: _______]` Bucket Versioning
  ➔ **TEST:** `mc version info minio7/teqlif` komutu `enabled` döndürdü.

---

## Faz 7 — Gateway (gateway1 + gateway2)

*Faz 5 bittikten sonra paralel yürütülebilir.*

### 7.1 — nginx Kurulumu

- [ ] `[Commit: _______]` nginx kur + yapılandır
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` `api.teqlif.com` server block: proxy → `10.10.0.10:8000` (VIP); WebSocket upgrade; `client_max_body_size 5m`
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` `staging.teqlif.com` server block: proxy → `10.10.0.4:8000` (node3 WG IP)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `www.teqlif.com` server block: static assets + well-known (App Links)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` WebSocket map: upgrade header doğru; `'' ''` (boş string — not close)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `proxy_cache_path` bypass (API dinamik içerik)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` upstream keepalive 32 (TCP bağlantı yeniden kullanımı)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `nginx.service.d/restart.conf` → `Restart=always`
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now nginx`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.

### 7.2 — Cloudflare Origin Certificate

- [ ] `[Commit: _______]` CF Dashboard → SSL/TLS → Origin Certificates → yeni sertifika → `cf-origin.crt` + `cf-origin.key`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/ssl/teqlif/` → `chmod 600 cf-origin.key`
  ➔ **TEST:** `ls -l` ile dosya izinlerinin doğruluğunu teyit et.

### 7.3 — Guardian Metrics + Promtail

- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable + start (her iki gateway)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Promtail kur → log stream node9 Loki'ye
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` nginx `stub_status` aktif: `location /nginx_status`
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.

### 7.4 — Cloudflare DNS — Gateway

- [ ] `[Commit: _______]` `api.teqlif.com` → gateway1 IP + gateway2 IP (CF Proxied, iki A record)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif.com` + `www.teqlif.com` → gateway1 + gateway2 (CF Proxied)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 7.5 — Guardian — gateway1 + gateway2

- [ ] `[Commit: _______]` `edge:metrics:gateway1/2` → orch-redis'te mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 7.6 — Faz 7 Doğrulama

- [ ] `[Commit: _______]` Proxy Ping
  ➔ **TEST:** `curl -I https://api.teqlif.com/v1/ping` -> `200 OK` ve Cloudflare (CF-RAY) header'ları mevcut.
- [ ] `[Commit: _______]` WebSocket Testi
  ➔ **TEST:** Gateway üzerinden WS bağlantısı 10 saniyeden uzun kopmadan açık kalabiliyor.
- [ ] `[Commit: _______]` Presigned Upload Bypass
  ➔ **TEST:** Gateway Nginx loglarında (access.log), dosya yükleme (PUT) için `Content-Length > 100KB` bir istek görülmedi.

---

## Faz 8 — Stream + AI Proxy

*Faz 5 bittikten sonra paralel yürütülebilir.*

### 8.1 — LiveKit SFU — node1 ve node4

- [ ] `[Commit: _______]` LiveKit binary GitHub releases'den indir → `/usr/local/bin/livekit-server`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/livekit/livekit.yaml`: TURN `relay_range_start: 50000` + `relay_range_end: 60000` (UFW ile eşleşmeli)
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.
- [ ] `[Commit: _______]` `livekit.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Promtail kur, guardian enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 8.2 — AI Proxy — node2

- [ ] `[Commit: _______]` `git clone` + venv + pip install (backend)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/teqlif/.env.production` → `GROQ_API_KEY`, `GEMINI_API_KEY`, `AI_PROXY_INTERNAL_TOKEN`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-ai-proxy.service` → enable + start (node2 = Primary, her zaman çalışır)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 8.3 — Guardian — node2

- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `edge:metrics:node2` → orch-redis'te mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 8.4 — Faz 8 Doğrulama

- [ ] `[Commit: _______]` LiveKit SFU
  ➔ **TEST:** `curl -s http://10.10.0.1:7880/` -> `200 OK` (node1/node4).
- [ ] `[Commit: _______]` AI Proxy (Node2)
  ➔ **TEST:** `curl -s http://10.10.0.3:8001/health` -> `200 OK`.
- [ ] `[Commit: _______]` AI Proxy Orchestrator
  ➔ **TEST:** `redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url` node2 adresini döndürdü.
- [ ] `[Commit: _______]` Cloudflare DNS: `live1.teqlif.com` → node1 IP (DNS Only); `live2.teqlif.com` → node4 IP (DNS Only)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 8.5 — AI Proxy Fallback — node3 (İlk Yedek)

- [ ] `[Commit: _______]` node3: `teqlif-ai-proxy.service` enable + start (Warm Standby — her zaman çalışır, `--host 0.0.0.0` — lokal staging ve prod mesh `10.10.0.4:8001` erişimini birlikte karşılar)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Orchestrator node2 down → `ai_proxy:active_url` → `http://10.10.0.4:8001` (node3) otomatik güncellemeli
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 9 — Guardian Koordinatör

**Önkoşul:** Faz 5 + 6 + 7 + 8 tamamlandı.

### 9.1 — Guardian Agent (Metrik) Doğrulaması

- [ ] `[Commit: _______]` `redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"` → 10 anahtar (gateway1, gateway2, node1..node8)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `type edge:metrics:node7` → hash
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Tüm Ajan Metrikleri
  ➔ **TEST:** Redis'teki `edge:metrics:*` anahtarlarında toplam 11 sunucunun listelendiği teyit edildi.

### 9.2 — Guardian Aktif + AI Proxy Routing

- [ ] `[Commit: _______]` Tüm node'larda `systemctl is-active teqlif-guardian` → active
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `redis-cli ... get ai_proxy:active_url` → nil (node2 aktif) veya node2 URL'si
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` node2/node3/node5 `edge:metrics` TTL'leri → 1-6 arası
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 9.3 — Dual-Write Routing Doğrulama

- [ ] `[Commit: _______]` `redis-cli ... get orch:best:storage_nodes` → `["node7","node8"]`
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` Test yükleme → her iki storage node'da `mc ls` ile doğrula
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 9.4 — Failover Simülasyonu — Storage

- [ ] `[Commit: _______]` Storage Failover Testi
  ➔ **TEST:** Node8 MinIO servisi durduruldu, sistemin 10-15sn içinde `orch:best:storage_nodes` değerini `["node7"]` olarak güncellediği görüldü.
- [ ] `[Commit: _______]` Telegram #ops bildirimi geldi mi?
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node8 geri getir → `orch:best:storage_nodes` → `["node7","node8"]`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 9.5 — Failover Simülasyonu — AI Proxy

- [ ] `[Commit: _______]` AI Proxy Failover Testi
  ➔ **TEST:** Node2 `teqlif-ai-proxy` durduruldu, sistemin aktif URL'yi Node3 (`http://10.10.0.4:8001`) olarak güncellediği doğrulandı.
- [ ] `[Commit: _______]` API AI çağrısı → node3 üzerinden → 200
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node2 geri getir → `ai_proxy:active_url` → node2 (otomatik failback)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 10 — Monitoring + Backup + ClickHouse (node9)

### 10.0 — node9 Ön Kurulum

- [ ] `[Commit: _______]` OS temeli (Faz 1) + WireGuard (Faz 2) + OS tuning (§3.5) → node9'a uygula
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/data` mount doğrula: `df -h /data` → 3.5 TB HDD RAID-1
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Backup dizin yapısı: `/data/teqlif_backups/{postgres/{wal,basebackup,dump},redis,minio}`, `/data/clickhouse-backups`, `chown tucibeyin`
  ➔ **TEST:** `ls -ld <dizin>` ile sahipliğin tucibeyin:tucibeyin olduğunu teyit et.
- [ ] `[Commit: _______]` Symlink: `ln -sfn /data/teqlif_backups /opt/teqlif/backups`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `node.conf`: guardian_priority=5
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` ClickHouse kur: packages.clickhouse.com repo → `clickhouse-server` + `clickhouse-client`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` ClickHouse `config.d/teqlif.xml`: `max_server_memory_usage=24GB` (node9 OOM önlemi)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` ClickHouse DB + kullanıcı oluştur; pg_hba.conf'a node9 WAL replica girişi ekle (node5'te)
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.

### 10.1 — Guardian — node9

- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `edge:metrics:node9` → orch-redis mevcut; guardian_priority=5 (lider seçilmez)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 10.2 — Prometheus

- [ ] `[Commit: _______]` Prometheus binary GitHub releases'den indir → `/usr/local/bin/prometheus`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `prometheus.yml`: 11 node scrape (her node 10.10.0.x:9200); scrape_interval=15s; retention=30d
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Alertmanager rules: NodeDown, ServiceFailed, GatewayDown, StorageNodeDown, HighCPU, MonitorDiskHigh, WALLag
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `prometheus.service` → `--web.listen-address=10.10.0.13:9090` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 10.3 — Grafana

- [ ] `[Commit: _______]` Grafana apt repo → kur
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `grafana.ini`: `http_addr=10.10.0.13` (WG-only — internete kapalı)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Data source: Prometheus `http://10.10.0.13:9090` + Loki `http://10.10.0.13:3100`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now grafana-server`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.
- [ ] `[Commit: _______]` Admin şifresini değiştir
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 10.4 — Loki + Promtail (node9)

- [ ] `[Commit: _______]` Loki Grafana apt repo'dan kur
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `loki.yaml`: listen_address=`10.10.0.13:3100`; retention=7d
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node9 Promtail kur → lokal logları node9 Loki'ye gönder
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl enable --now loki`
  ➔ **TEST:** `systemctl is-enabled --now` çıktısının enabled olduğunu teyit et.

### 10.5 — Alertmanager → Telegram

- [ ] `[Commit: _______]` Alertmanager binary indir → `/usr/local/bin/alertmanager`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `alertmanager.yml`: Telegram webhook, `#ops` kanalı, inhibit_rules (NodeDown → warning suppress)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `alertmanager.service` → `--web.listen-address=10.10.0.13:9093` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 10.6 — Yedekleme

- [ ] `[Commit: _______]` **10.6.1 Kurulum:** backup scriptleri → `/usr/local/bin/`; tüm systemd service + timer dosyaları → enable
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` **10.6.2 pg_receivewal:** `teqlif-pg-receivewal.service` → `pg_receivewal -h 10.10.0.10 -U replicator --slot=wal_backup_node9 --compress=9 -D /data/teqlif_backups/postgres/wal/` → start
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` **10.6.3 pg_basebackup:** haftalık timer → `pg_basebackup -h 10.10.0.10 -U replicator -D /data/teqlif_backups/postgres/basebackup/...`; atomic temp→rename
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` **10.6.4 pg_dump:** günlük timer → `pg_dump -h 10.10.0.10 -U teqlif teqlif | gzip`; eski dumplar temizle
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` **10.6.6 Redis RDB:** haftalık timer → `redis-cli --rdb /tmp/...`; atomic temp→rename
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` **10.6.7 ClickHouse yedek:** günlük timer → `clickhouse-backup create`; 2 günden eski localler sil
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` **10.6.8 MinIO soğuk arşiv:** günlük timer (02:00 UTC) → `minio_backup.sh`; node7 primary (node8 fallback); `teqlif` + `teqlif-dm` bucket'ları → `/data/backups/minio/` lokal arşive `mc mirror --overwrite --remove`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` **10.6.9 Off-site rclone:** günlük timer → `rclone sync /data/teqlif_backups b2backup:teqlif-backups`; B2 retention 7d
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` **10.6.11 WG private key kurtarma:** tüm 11 node private key'ini şifreli biçimde password manager'a kaydet
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 10.7 — Faz 10 Doğrulama

- [ ] `[Commit: _______]` `systemctl is-active prometheus loki alertmanager grafana-server` → tümü active
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Prometheus Targets
  ➔ **TEST:** `curl -s http://10.10.0.13:9090/api/v1/targets` -> `11 target UP` durumu doğrulandı.
- [ ] `[Commit: _______]` Backup (pg_receivewal)
  ➔ **TEST:** `systemctl is-active teqlif-pg-receivewal` -> `active` ve `/data/teqlif_backups/postgres/wal/` dizininde WAL dosyaları birikiyor.
- [ ] `[Commit: _______]` Backup (Cron)
  ➔ **TEST:** `/data/teqlif_backups/postgres/dump/` dizininde test dump dosyası oluştu.
- [ ] `[Commit: _______]` Off-site Sync
  ➔ **TEST:** `rclone lsd b2backup:` -> Cloud depolama bucket'ı başarıyla listelendi.
- [ ] `[Commit: _______]` Grafana Dashboard
  ➔ **TEST:** `http://10.10.0.13:3000` üzerinden giriş yapılıp, Loki loglarının ve metriklerin tek panelde görülebildiği teyit edildi.

---

## Faz 11 — Staging (node3)

### 11.1 — PostgreSQL — node3 Lokal

- [ ] `[Commit: _______]` PGDG repo → `postgresql-17` kur (node3)
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `teqlif_staging` DB + `teqlif` user (staging şifresi)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `pg_hba.conf`: lokal bağlantı izin
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.

### 11.2 — Redis — node3 Lokal

- [ ] `[Commit: _______]` `redis-staging.conf` → `cp resources/redis/redis-staging.conf /etc/redis/`; `sed` ile `<staging_redis_pass>` doldur
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` `redis-staging.service` → enable + start
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 11.3 — MinIO — node3 Lokal (staging)

- [ ] `[Commit: _______]` MinIO binary indir + mc client
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/data/minio-staging` data dir
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `minio-staging.service` → enable + start; `MINIO_SERVER_URL=https://uploads-staging.teqlif.com`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` mc alias: staging bucket'ları oluştur; versioning aktif
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` UFW: `deny 9000/tcp` (MinIO doğrudan internet'e kapalı)
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.

### 11.4 — LiveKit — node3 Lokal (staging)

- [ ] `[Commit: _______]` LiveKit binary indir
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/livekit/livekit-staging.yaml`: staging API key/secret; TURN relay_range eşleşmeli UFW ile
  ➔ **TEST:** `ufw status verbose` ile kuralların aktif olduğunu teyit et.
- [ ] `[Commit: _______]` `livekit-staging.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 11.5 — Staging App

- [ ] `[Commit: _______]` `git clone` + venv + pip install (node3)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `/etc/teqlif/.env.staging` → template'den doldur (lokal PG, lokal Redis, lokal MinIO)
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` Firebase: `firebase-service-account.json` → `/etc/teqlif/` (güvenli kanaldan kopyala — repoya GİRMEZ)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` APNS: `AuthKey_*.p8` → `/etc/teqlif/` (güvenli kanaldan kopyala — repoya GİRMEZ)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-staging.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-worker-staging.service` + `teqlif-worker-critical-staging.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-ai-proxy.service` (staging + prod fallback, `--host 0.0.0.0`) → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-guardian.service.d/staging-env.conf` drop-in → `.env.staging` kullan
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `teqlif-guardian.service` → enable + start
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Alembic: `cd backend && .venv/bin/python -m alembic upgrade head`
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 11.6 — nginx (staging.teqlif.com — node3)

- [ ] `[Commit: _______]` `cp resources/nginx/sites-available/staging /etc/nginx/sites-available/`
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` `ln -s` → sites-enabled
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` CF Origin cert kopyala
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `nginx -t && systemctl reload nginx`
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.

### 11.7 — Faz 11 Doğrulama

- [ ] `[Commit: _______]` `systemctl is-active teqlif-staging teqlif-worker-staging teqlif-ai-proxy redis-staging minio-staging livekit-staging` → tümü active
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` Staging Core Health
  ➔ **TEST:** `curl -s http://127.0.0.1:8000/v1/ping` -> `200 OK`
- [ ] `[Commit: _______]` `curl -s http://127.0.0.1:8001/health` → 200 (AI proxy)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `ls /etc/teqlif/firebase-service-account.json` → dosya mevcut
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Guardian: `edge:metrics:node3` → orch-redis'te mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.

### 11.8 — Entegrasyon Testleri

- [ ] `[Commit: _______]` Staging ortamında uçtan uca kullanıcı akışı test et (auth, upload, stream, AI çağrısı)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Cloudflare DNS: `staging.teqlif.com` → gateway1 + gateway2 → node3
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 12 — Prodüksiyon + Mobile

### 12.1 — Son Kontrol Listesi

- [ ] `[Commit: _______]` DNS Doğrulama (API)
  ➔ **TEST:** `api.teqlif.com` -> Sadece Gateway IP'leri (Cloudflare Proxied).
- [ ] `[Commit: _______]` DNS Doğrulama (Media/Upload)
  ➔ **TEST:** `uploads.teqlif.com` -> Node7 ve Node8 IP'leri (Cloudflare DNS Only).
- [ ] `[Commit: _______]` node5: teqlif + teqlif-worker + teqlif-worker-critical + teqlif-guardian → active
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `orch:best:storage_nodes = ["node7","node8"]` doğrula
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node6: keepalived active; teqlif/worker disabled; teqlif-guardian active
  ➔ **TEST:** `ip addr show` ile VIP atanmasını veya `systemctl status keepalived` çıktısını teyit et.
- [ ] `[Commit: _______]` node7 + node8: minio + nginx + teqlif-guardian → active
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` Prometheus: 11 target UP
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Loki: 11 node'dan log akışı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Alertmanager: test alert gönder → Telegram'da görün
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Upload Akışı (Presigned S3 Bypass)
  ➔ **TEST:** Mobile'dan resim yüklendiğinde; PUT isteğinin Gateway'den değil, `uploads.teqlif.com` adresinden direkt Storage node'larına ulaştığı loglardan kesinleşti.
- [ ] `[Commit: _______]` Tüm `UploadFile` endpoint'leri kaldırıldı → gateway log'unda Content-Length > 100KB POST yok
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `nginx -T | grep client_max_body_size` → 5m (gateway)
  ➔ **TEST:** `nginx -t` ile syntax hatası olmadığını teyit et.
- [ ] `[Commit: _______]` Dual-write: medya yükle → her iki storage node'da mc ls ile doğrula
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` MinIO versioning: `mc version info minio7/teqlif` → enabled
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `systemctl is-active teqlif-pg-receivewal` → active; WAL birikiyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` İlk pg_dump başarılı: dosya mevcut
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` Off-site Sync
  ➔ **TEST:** `rclone lsd b2backup:` -> Cloud depolama bucket'ı başarıyla listelendi.
- [ ] `[Commit: _______]` WireGuard private key'ler password manager'a kaydedildi (tüm 11 node)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 12.2 — Mobile Güncellemesi

- [ ] `[Commit: _______]` `dart_defines/release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` güncelle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `dart_defines/staging.json`: aynı anahtarlar staging değerleriyle
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `frontend/.well-known/assetlinks.json` — Android App Links
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `frontend/.well-known/apple-app-site-association` — iOS Universal Links
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Android: Play Store internal track
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` iOS: App Store TestFlight
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## Faz 13 — node9 Doğrulama + Tam Entegrasyon

### 13.1 — WireGuard Mesh Bütünlüğü

- [ ] `[Commit: _______]` node9'dan tüm 10 node'a ping → tümü OK
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Diğer node'lardan node9'a ping → OK
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` `wg show wg0` her node'da → Latest handshake < 5 dakika
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 13.2 — ClickHouse — Prod Veri Akışı Doğrulaması

- [ ] `[Commit: _______]` ClickHouse Veri Akışı
  ➔ **TEST:** `SELECT count() FROM teqlif.analytics_events` komutunda, uygulamada yapılan aksiyonlarla birlikte satır sayısının arttığı görüldü.
- [ ] `[Commit: _______]` Circuit Breaker
  ➔ **TEST:** Node9 kapatıldığında (veya ClickHouse durdurulduğunda), Core App (Node5) canlı kalmaya, hata vermeden çalışmaya ve API isteklerine yanıt vermeye devam etti.

### 13.3 — Prometheus — Tüm Node'lar Scrape Ediliyor

- [ ] `[Commit: _______]` `curl http://10.10.0.13:9090/api/v1/targets` → 11 target UP
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Her node'dan Prometheus metrikleri görünüyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 13.4 — Loki — Tüm Node'lardan Log Akışı

- [ ] `[Commit: _______]` Loki (Promtail)
  ➔ **TEST:** `curl "http://10.10.0.13:3100/loki/api/v1/labels"` -> Node label'ları listelendi.
- [ ] `[Commit: _______]` Grafana Loki explorer'da 11 node log'ları mevcut
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 13.5 — Backup Sistemleri — İlk Tam Doğrulama

- [ ] `[Commit: _______]` `pg_receivewal`: WAL lag < 10 MB; .gz.partial dosyaları birikiyor
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `pg_dump`: ilk dump mevcut, < 24 saatlik
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` `clickhouse-backup`: `/data/clickhouse-backups/ch_backup_*` mevcut
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Redis backup: `/opt/teqlif/backups/redis/` mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` Off-site rclone: `rclone lsd b2backup:` → bucket görünüyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 13.6 — Alertmanager — Telegram Testi

- [ ] `[Commit: _______]` Alertmanager Telegram Testi
  ➔ **TEST:** Test alarmı tetiklendiğinde Telegram `#ops` kanalına mesaj düştü.

### 13.7 — Grafana — Dashboard Doğrulaması

- [ ] `[Commit: _______]` Prometheus + Loki data source bağlı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` node9 metrikleri dashboard'da görünüyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Admin şifresi varsayılandan değiştirildi
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

### 13.8 — Guardian — node9 Entegrasyon Durumu

- [ ] `[Commit: _______]` `edge:metrics:node9` güncel → guardian_priority=5 → lider seçilmedi (node5/6 öncelikli)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Guardian Liderlik Durumu
  ➔ **TEST:** Node9'un `guardian_priority=5` olduğu için kendisini hiçbir zaman lider ilan etmediği, liderin 1 veya 2 numaralı Node'larda (Core) kaldığı teyit edildi.

### 13.9 — Son Kontrol Listesi

- [ ] `[Commit: _______]` WireGuard: node9 ↔ tüm 10 node çift yönlü handshake OK
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` ClickHouse: analytics_events satır sayısı artıyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Prometheus: 11 target UP (node9 dahil)
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Loki: 11 node log akışı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` pg_receivewal: WAL lag < 10 MB
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` pg_dump: ilk dump dosyası mevcut, < 24 saatlik
  ➔ **TEST:** `systemctl status postgresql` veya `psql -U teqlif -c '\conninfo'` ile durumu teyit et.
- [ ] `[Commit: _______]` ClickHouse backup dosyaları mevcut
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Redis backup dosyaları mevcut
  ➔ **TEST:** `redis-cli ping` komutunun PONG döndüğünü teyit et.
- [ ] `[Commit: _______]` Alertmanager Telegram testi geçti
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Grafana: her iki data source bağlı, dashboard çalışıyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Guardian: node9 lider seçilmedi, edge:metrics güncel
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Circuit breaker: ClickHouse kapatılınca app canlı kalıyor
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.
- [ ] `[Commit: _______]` Off-site rclone bağlantısı doğrulandı
  ➔ **TEST:** İlgili yapılandırmanın çalıştığını ve loglarda hata olmadığını teyit et.

---

## İlerleme Özeti

| Faz | Konu | Durum |
|-----|------|-------|
| §0.0 | Secrets Üretimi | [ ] |
| Faz 0 | Kod Hazırlığı (Lokalde) | [ ] |
| Faz 1 | OS Temeli — Tüm Node'lar | [ ] |
| Faz 2 | WireGuard Mesh | [ ] |
| Faz 3 | Rol Bazlı OS Tuning | [ ] |
| Faz 4 | Veri Katmanı HA (node5 + node6) | [ ] |
| Faz 5 | Core App (node5 + node6) | [ ] |
| Faz 6 | Storage (node7 + node8) | [ ] |
| Faz 7 | Gateway (gateway1 + gateway2) | [ ] |
| Faz 8 | Stream + AI Proxy | [ ] |
| Faz 9 | Guardian Koordinatör | [ ] |
| Faz 10 | Monitoring + Backup + ClickHouse (node9) | [ ] |
| Faz 11 | Staging (node3) | [ ] |
| Faz 12 | Prodüksiyon + Mobile | [ ] |
| Faz 13 | node9 Doğrulama + Tam Entegrasyon | [ ] |
