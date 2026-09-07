# Teqlif Scale Planı — V1.0
> **Hostname eşleştirme:** `node1` = OVH Frankfurt (ana backend) | `gateway` = Netcup Nürnberg (edge proxy + observability)
> **Tarih:** 2026-09-07 | **Durum:** Taslak

---

## 1. Mevcut Durum — node1 (OVH Frankfurt)

### Donanım
| Parametre | Değer |
|---|---|
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 12 GiB Swap |
| Disk | 98.3 GiB NVMe |
| Ağ | **2 Gbps / unmetered** (kota yok) |
| Geekbench 6 | 1058 single / 4404 multi |

### node1 Kaynak Tüketicileri (Büyükten Küçüğe)

**1. LiveKit — Bant Genişliği + CPU**
WebRTC SFU; sesli/görüntülü aramada gerçek zamanlı UDP medya akışları işler. Aktif arama başına ~1-4 Mbps upstream + downstream. OVH'ın unmetered 2Gbps hattının doğrudan faydalanıcısı. Kesinlikle node1'de kalmalı — UDP proxy edilemez, bant genişliği kritik.

**2. ARQ Workers (ML) — CPU + RAM**
`worker.py`'de ML ağırlıklı görevler:
- `generate_embedding_task` / `generate_listing_embedding_task` — PyTorch sentence-transformer (384 boyutlu vektör). Kod yorumu: *"thread-blocking yaptığı için FastAPI'den ayrı çalışmalıdır"*
- `update_user_preference_embedding` — numpy ağırlıklı ortalama vektör hesabı
- `train_bpr_task` (Cumartesi 03:00) — BPR collaborative filtering modeli
- `train_item2vec_task` (Pazar 04:00) — Item2Vec modeli
- `train_kmeans_cold_start_task` (Pazar 05:00) — 50-cluster K-Means
- `train_listing_quality_model_task` (Pazar 02:30) — GradientBoostingRegressor

Bu işler PostgreSQL + ClickHouse'a doğrudan, düşük gecikmeli erişim gerektirir. Gateway'e taşınamaz (2 vCPU + 1.9GB RAM yetersiz; PyTorch model tek başına ~300-500MB alır).

**3. ClickHouse — RAM + CPU**
Her 5 dakikada `flush_interactions_to_db` bulk insert. Her 15-20 dakikada karmaşık analitik sorgular (`compute_user_interests`, `sync_swipelive_interests`). Columnar engine RAM'e agresif; PostgreSQL ve Redis ile RAM rekabeti yaşar.

**4. PostgreSQL — RAM + Disk I/O**
`shared_buffers`, bağlantı havuzu, worker sorgularının çoğu buraya yüklenip buradan okunur. Disk I/O analitik yazma + normal OLTP yazmayla paylaşılıyor.

**5. Redis — RAM**
4 GB `maxmemory`. Relationship cache, feed cache, call presence, ARQ kuyrukları, interaction queue, Thompson Sampling parametreleri, embedding cursor. Tüm sistem buraya bağlı — tek SPOF.

**6. MinIO — Disk + Bant Genişliği**
`teqlif` (public) + `teqlif-dm` (private) bucket. Upload/download trafiği; DM medya temizlik worker'ı her gün MinIO'ya erişir. OVH unmetered hat dolaylı faydalanıcı.

**7. FastAPI (prod + staging) — Orta CPU/RAM**
Stateless; tüm durumu Redis/PostgreSQL'de. Gecikmesi düşük tutulmalı → DB/Redis ile aynı node'da kalması avantajlı.

**8. Prometheus + Loki — RAM + Disk**
Prometheus TSDB scrape + retention. Loki log indexing. Her ikisi de RAM tüketir (~500MB-1GB toplam) ve üretim yükünden bağımsız olmalı — monitoring, izlediği sistemin kaynaklarını yememeli. **Bu servislerin gateway'e taşınması node1'e ~500MB-1GB RAM iade eder.**

---

## 2. Yeni Makine — gateway (Netcup Nürnberg)

### Donanım
| Parametre | Değer |
|---|---|
| CPU | 2 vCore (QEMU @ 2.29 GHz) |
| RAM | 2 GB + 1 GB Swap |
| Disk | 60 GB SSD (genişletilemiyor) |
| Ağ | 1 Gbps interface — **24h ortalama >100 Mbps → geçici throttle (100 Mbps)** |
| Geekbench 6 | 645 single / 1210 multi |

### Değerlendirme
1.9 GB RAM, ML worker, PostgreSQL replica veya ClickHouse barındırmak için yetersiz. Ağır iş yapacak bir backend node'u değil.

**Güçlü yanları:**
- 1 Gbps interface → nginx proxy için fazlasıyla yeterli; monitoring trafiği 24h ortalaması 100 Mbps'nin çok altında kalır
- 60 GB SSD → Prometheus TSDB + Loki log storage için ideal (node1'in daralan diski yerine)
- Düşük işletim maliyeti → daimi servis için uygun
- node1'den bağımsız çalışır → monitoring node1 çöktüğünde de ayakta kalabilir

**Ağ kısıtı — dikkat:**
24 saatlik ortalama trafik 100 Mbps'yi aşarsa Netcup geçici throttle uygular (ortalama düşünce otomatik kalkar). Bu nedenle büyük dosya upload/download trafiğinin gateway üzerinden **geçmemesi** kritik. Video yükleme gibi burst trafik `uploads.teqlif.com` → node1 doğrudan yönlendirmesiyle gateway'i atlamalı.

**Rol: Edge Proxy + Observability Node**

---

## 3. Önerilen Mimari — V1.0

```
İnternet
    │
    ▼
[gateway — Netcup Nürnberg]          [node1 — OVH Frankfurt]
  nginx  (SSL termination)    ──────▶   FastAPI prod
  Tailscale (VPN tüneli)      ◀──────   FastAPI staging
  Prometheus (scrape her ikisini)        PostgreSQL
  Loki  (her ikisinden log)              Redis
  promtail                               MinIO
  node_exporter                          ClickHouse
  fail2ban                               LiveKit  (UDP — gateway bypass)
                                         ARQ Workers (ML + DB)
                                         nginx (iç)
                                         Tailscale
                                         node_exporter
                                         promtail → gateway Loki
                                         fail2ban
```

### Trafik Akışı
```
Client  ──HTTP/WS──▶  gateway:443 (nginx SSL)
                            │ Tailscale şifreli tünel
                            ▼
                       node1:8000 (FastAPI)

LiveKit WebRTC medya (UDP):
Client  ──UDP──▶  node1 doğrudan  (gateway bypass — proxy edilemez)

Monitoring:
node1 node_exporter/promtail  ──Tailscale──▶  gateway Prometheus/Loki
```

### LiveKit İstisnası (Kritik)
WebRTC medya UDP kullanır, nginx üzerinden proxy **edilemez**. LiveKit sinyalizasyonu (`/rtc` WSS) gateway üzerinden proxy edilir; medya akışı (STUN/TURN/ICE) için node1'in public IP'si doğrudan erişilebilir kalır. node1 firewall'unda LiveKit UDP portları herkese açık tutulur.

---

## 4. Servis Dağılımı

| Servis | node1 (OVH) | gateway (Netcup) | Karar Gerekçesi |
|---|---|---|---|
| PostgreSQL | ✅ | ❌ | RAM + disk, worker'ların doğrudan erişimi |
| Redis | ✅ | ❌ | Tüm sistem tek bağımlılık |
| MinIO | ✅ | ❌ | Disk + OVH unmetered bant |
| ClickHouse | ✅ | ❌ | RAM yoğun, worker entegrasyonu |
| LiveKit | ✅ | ❌ | UDP medya + OVH unmetered bant |
| FastAPI prod | ✅ | ❌ | DB/Redis yakınlığı kritik |
| FastAPI staging | ✅ | ❌ | Aynı nedenle |
| ARQ Workers | ✅ | ❌ | ML (PyTorch/numpy) + DB/ClickHouse erişimi |
| nginx (iç) | ✅ | — | Sadece iç yönlendirme |
| **nginx (public)** | ❌ → iç | ✅ | SSL termination, edge |
| **Prometheus** | ❌ → taşınır | ✅ | Observability bağımsızlığı; node1'e ~300MB RAM iade |
| **Loki** | ❌ → taşınır | ✅ | Log storage için 58.9GB disk avantajı |
| **Grafana** | ❌ kaldırıldı | ❌ | Prometheus + Loki alert'leri yeterli |
| promtail | ✅ (node1 log → gateway) | ✅ (kendi logu) | Her iki node'da, gateway Loki'ye gönderir |
| node_exporter | ✅ | ✅ | Her iki node'da, gateway Prometheus scrape eder |
| Tailscale | ✅ | ✅ | Özel ağ tüneli |
| fail2ban | ✅ | ✅ | Bağımsız |

---

## 5. Grafana Kaldırma Kararı

Grafana sadece görselleştirme katmanı — veri üretmiyor, saklamıyor. Alert pipeline'ına dokunmuyor. Prometheus'un kendi alert kuralları (`alerting_rules.yml`) + Alertmanager ve Loki'nin kendi alert kuralları Grafana olmadan tam işlevsel çalışır. Servis kaldırıldı; RAM ve yönetim yükü azaltıldı.

---

## 6. Değişiklik Gereksinimleri

### Uygulama kodu — sıfır değişiklik
- `settings.redis_url` → node1 localhost, değişmez
- `settings.database_url` → node1 localhost, değişmez
- `database_clickhouse.py` → `host="localhost"` hardcoded, ClickHouse node1'de kalır, değişmez
- `settings.minio_dm_external_url` → zaten dış domain, değişmez
- `ws_manager` → Redis Stream fan-out zaten multi-node hazır
- CORS → `main.py`'de `teqlif.com` / `www.teqlif.com` sabitleri, gateway IP CORS'u etkilemez

### Deploy config — 3 değişiklik gerekli

**1. `deploy/promtail-config.yml` — Loki hedefini gateway'e yönlendir**

`clients.url` şu an `http://localhost:3100/...`. Prometheus + Loki gateway'e taşınınca:
```yaml
clients:
  - url: http://<GATEWAY_TAILSCALE_IP>:3100/loki/api/v1/push
```

**2. node1 uvicorn — proxy IP güveni**

Gateway → Tailscale → node1:8000 zincirinde `request.client.host` gateway Tailscale IP'si olur. `main.py` X-Forwarded-For header'ını okuyarak gerçek client IP'yi alıyor, bu doğru çalışır. Ancak güvenlik için uvicorn'a sadece gateway Tailscale IP'sini güvenilir proxy olarak tanıtmak gerekir:
```bash
# teqlif.service ExecStart'a ekle:
--forwarded-allow-ips=<GATEWAY_TAILSCALE_IP>
```
Bu olmadan herhangi biri node1'e doğrudan erişebilseydi (firewall öncesi) sahte X-Forwarded-For gönderebilirdi. Firewall sertleştirme bunu zaten engeller, ama defense-in-depth açısından önerilir.

**3. gateway nginx — `/rtc` LiveKit sinyalizasyon proxy'si**

`settings.livekit_url = "wss://teqlif.com/rtc"` — istemciler WebSocket bağlantısını `/rtc` path'i üzerinden kurar. gateway nginx'e bu location **eksikse LiveKit sinyalizasyonu çalışmaz**. Detay Adım 3'te (nginx config bloğunda `/rtc` upstream ayrı tanımlandı).

---

## 7. Uygulama Adımları

### Adım 1 — Tailscale Kurulumu (Sıfır downtime)
```bash
# Her iki node'da
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Bağlantı testi (gateway'den)
ping <NODE1_TAILSCALE_IP>
```

### Adım 2 — Prometheus + Loki'yi gateway'e Kur
```bash
# gateway'de
# Prometheus
wget https://github.com/prometheus/prometheus/releases/download/.../prometheus-*.linux-amd64.tar.gz
# Loki
wget https://github.com/grafana/loki/releases/download/.../loki-linux-amd64.zip
```

`prometheus.yml` (gateway'de):
```yaml
scrape_configs:
  - job_name: node1
    static_configs:
      - targets: ['<NODE1_TAILSCALE_IP>:9100']
    labels: {node: node1}

  - job_name: gateway
    static_configs:
      - targets: ['localhost:9100']
    labels: {node: gateway}

  - job_name: postgres
    static_configs:
      - targets: ['<NODE1_TAILSCALE_IP>:9187']
```

node1'de `promtail.yml` hedefini gateway Loki'ye yönlendir:
```yaml
clients:
  - url: http://<GATEWAY_TAILSCALE_IP>:3100/loki/api/v1/push
```

### Adım 3 — gateway nginx Yapılandırması
```nginx
# /etc/nginx/sites-enabled/teqlif.conf

upstream node1_api {
    server <NODE1_TAILSCALE_IP>:8000;
    keepalive 32;
}

# LiveKit sinyalizasyon (HTTP API) — sadece signaling, medya UDP doğrudan node1'e gider
upstream node1_livekit {
    server <NODE1_TAILSCALE_IP>:7880;
    keepalive 8;
}

server {
    listen 443 ssl http2;
    server_name teqlif.com www.teqlif.com;

    ssl_certificate     /etc/letsencrypt/live/teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/teqlif.com/privkey.pem;

    # LiveKit WebSocket sinyalizasyon — settings.livekit_url = "wss://teqlif.com/rtc"
    # KRITIK: Bu location eksikse LiveKit sesli/görüntülü arama çalışmaz
    location /rtc {
        proxy_pass         http://node1_livekit;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # API + WebSocket (DM, bildirim, feed)
    location / {
        proxy_pass         http://node1_api;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Büyük dosya upload — buffer kapat
    location /api/upload {
        proxy_pass              http://node1_api;
        proxy_buffering         off;
        proxy_request_buffering off;
        client_max_body_size    500m;
    }

    location /uploads/ {
        proxy_pass      http://node1_api;
        proxy_buffering off;
    }
}
```

### Adım 4 — node1 Firewall Sertleştirme
```bash
# HTTP/HTTPS sadece gateway Tailscale IP'sinden
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 80
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 443
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 8000

# Monitoring — sadece gateway'den
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 9100  # node_exporter
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 9187  # postgres-exporter

# LiveKit — herkese açık (UDP proxy edilemez)
sudo ufw allow 7880/tcp
sudo ufw allow 7881/tcp
sudo ufw allow 50000:60000/udp

# SSH — kısıtla veya Tailscale üzerinden
```

### Adım 5 — DNS Değişikliği
- `teqlif.com` A record → gateway public IP
- node1'in public IP'sini DNS'ten çıkar (LiveKit için açık port kalır)

### Adım 6 — Doğrulama Checklist
- [ ] API endpoint'leri yanıt veriyor
- [ ] WebSocket (DM, bildirim, feed) bağlantıları kuruluyor
- [ ] LiveKit WebRTC ICE başarılı (sesli/görüntülü arama)
- [ ] `/uploads/` dosyaları erişilebilir
- [ ] MinIO presigned DM URL'leri çalışıyor
- [ ] Prometheus gateway'den node1 metriklerini scrape ediyor
- [ ] Loki node1 loglarını alıyor
- [ ] Prometheus alert kuralları aktif

---

## 8. node1'e Kazandırılan Kapasite

| Servis taşındı | Tahmini RAM kazancı |
|---|---|
| Prometheus | ~300 MB |
| Loki | ~200-400 MB |
| Grafana (kaldırıldı) | ~150-250 MB |
| **Toplam** | **~650 MB – 950 MB** |

Bu kazanç direkt olarak PostgreSQL `shared_buffers`, Redis maxmemory artışı veya ML worker'ların peak dönemlerinde kullanılabilir.

---

## 9. Riskler

| Risk | Ağırlık | Önlem |
|---|---|---|
| **gateway SPOF** | Yüksek | DNS TTL kısalt (60s); node1 nginx'i hazır tut; gateway düşünce node1 doğrudan devreye girer |
| **Tailscale SaaS bağımlılığı** | Orta | Alternatif: WireGuard manuel kurulum (daha fazla efor, tam kontrol) |
| **Ekstra gecikme** | Düşük-Orta | Frankfurt↔Nürnberg ~10-15ms RTT; mobil API için +20-30ms — kabul edilebilir |
| **Büyük upload Tailscale tünelinden geçer** | Orta | Değerlendirme: `uploads.teqlif.com` subdomain'ini node1'e doğrudan yönlendirmek |

---

## 10. Açık Sorular

1. **Büyük upload bypass'ı** — Video yükleme (MB-GB boyutunda) Tailscale tünelinden geçmek zorunda. `uploads.teqlif.com` subdomain'i node1'e doğrudan A record bağlanabilir; upload trafiği gateway'i atlar.

2. **Nginx microcaching gateway'de** — Feed ve listing API yanıtları için 1-5 saniyelik mikro cache. WS ve chat endpoint'leri cache dışı. node1 yükünü ciddi ölçüde azaltır. V1.1 adayı.

3. **gateway SPOF fallback otomasyonu** — DNS TTL kısaltma yeterli mi, yoksa health-check tabanlı otomatik failover (Cloudflare, Route53 health check) gerekli mi?

---

## 11. Sonraki Fazlar (V2.0+)

| Faz | Ne | Tetikleyici |
|---|---|---|
| V1.1 | gateway'de nginx microcaching | node1 CPU %70+ sürekli |
| V1.2 | Büyük upload bypass (`uploads.teqlif.com` → node1 doğrudan) | Upload latency sorun olursa |
| V2.0 | PostgreSQL streaming read replica (node3) | Okuma sorguları yavaşlarsa |
| V2.1 | FastAPI replika (node3, daha büyük RAM) | API yanıt süresi bozulursa |
| V2.2 | Redis Sentinel + Replica | Redis SPOF kabul edilemez hale gelirse |
| V3.0 | MinIO distributed mode | Disk dolumu yaklaşırsa |
