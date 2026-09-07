# Teqlif Scale Planı — V1.0
> **Tarih:** 2026-09-07  
> **Durum:** Taslak — olgunlaştırma aşamasında

---

## 1. Mevcut Durum (Tek VPS — OVH Frankfurt)

### Donanım
| Parametre | Değer |
|---|---|
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 12 GiB Swap |
| Disk | 98.3 GiB NVMe |
| Ağ | ~1.94 Gbps uplink |
| Geekbench 6 | 1058 single / 4404 multi |

### Çalışan Servisler (systemd)
| Servis | Açıklama |
|---|---|
| `postgresql@17-main` | Birincil veritabanı |
| `redis-server` | Cache, kuyruk, stream, presence (4 GB maxmemory) |
| `minio` | Nesne depolama — `teqlif` (public) + `teqlif-dm` (private) bucket |
| `clickhouse-server` | Analitik veritabanı |
| `livekit` | WebRTC SFU — sesli/görüntülü arama |
| `nginx` | Web sunucusu — şu an dışarıya açık |
| `teqlif.service` | FastAPI backend (production) |
| `teqlif-staging.service` | FastAPI backend (staging) |
| `teqlif-worker.service` | ARQ arka plan worker |
| `teqlif-worker-critical.service` | ARQ kritik işlemler worker |
| `prometheus` + `grafana-server` | İzleme |
| `loki` + `promtail` | Log toplama |
| `node_exporter` + `postgres-exporter` | Prometheus metrik toplayıcıları |
| `fail2ban` | Brute-force koruması |

### Koddan Çıkan Mimari Tespitler

**WebSocket fan-out — zaten yatay ölçeklenebilir:**  
`ws_manager.publish()` Redis Stream'e (`XADD`) yazar. Her worker kendi pozisyonundan `XREAD` eder ve `broadcast_local()` ile kendi bağlantılarına dağıtır. Bu yapı, API worker'ları birden fazla makineye dağıtmaya hazır — hiçbir kod değişikliği gerekmez.

**Stateless API worker'lar:**  
Tüm oturum bilgisi Redis'te tutulur (relationship cache, call presence, feed cache, schema cache, idempotency key'leri). API process'leri durumsuz; herhangi bir node istekleri yanıtlayabilir.

**ARQ task queue — Redis tabanlı:**  
`teqlif-worker` ve `teqlif-worker-critical` Redis üzerinden iş alır. Worker'lar farklı bir node'da çalışabilir — sadece aynı Redis URL'ine erişmesi yeterli.

**MinIO presigned URL mimarisi:**  
`minio_dm_external_url` ayarı sayesinde DM bucket için presigned URL üretimi harici domain'den yapılıyor. Bu, MinIO'nun arkaya alınmasını kolaylaştırır.

**Tek sorun noktaları:**
- PostgreSQL, Redis, MinIO, ClickHouse, LiveKit hepsi aynı node'da → bu servislerin birine olan yük artışı diğerlerini etkiler
- `nginx` şu an hem SSL terminasyonu hem içerik sunumu yapıyor ve doğrudan dışarıya açık

---

## 2. Yeni VPS — Netcup Nürnberg

### Donanım
| Parametre | Değer |
|---|---|
| CPU | QEMU 2 vCPU @ 2.29 GHz |
| RAM | 1.9 GiB |
| Disk | 58.9 GiB NVMe |
| Ağ | ~1.07 Gbps uplink |
| Geekbench 6 | 645 single / 1210 multi |

### Değerlendirme
1.9 GB RAM, FastAPI replika, PostgreSQL replika veya herhangi bir ML servisi çalıştırmak için **yetersiz**. Bu node'u ağır iş yapacak bir backend node'u olarak konumlandırmak doğru değil.

**Güçlü yanı:** 1 Gbps hat + düşük işletim maliyeti → **edge proxy** rolüne birebir uygun.

---

## 3. Önerilen Mimari — V1.0 (Edge Proxy)

```
İnternet
    │
    ▼
[Node-2 — Netcup Nürnberg]
  nginx (SSL termination, reverse proxy)
  Tailscale (VPN tüneli)
    │
    │  Tailscale şifreli tünel
    │  Frankfurt ↔ Nürnberg ~10-15ms
    │
    ▼
[Node-1 — OVH Frankfurt]
  FastAPI (teqlif.service)
  PostgreSQL, Redis, MinIO
  ClickHouse, LiveKit
  ARQ Workers
  (nginx → sadece iç iletişim için)
```

### Trafik Akışı
```
Client → Node-2:443 (nginx SSL) → Tailscale → Node-1:8000 (FastAPI)
Client → Node-2:443 /uploads/* → Tailscale → Node-1 nginx/MinIO
Client ← Node-2 (yanıt)
```

**LiveKit istisnası (kritik):**  
WebRTC medya trafiği (sesli/görüntülü arama) UDP kullanır, nginx üzerinden proxy edilemez. LiveKit sinyalizasyonu (`/rtc` WSS) Node-2 üzerinden proxy edilir, ama **medya akışı (STUN/TURN/ICE) için Node-1'in public IP'si erişilebilir kalmalı**. LiveKit'in UDP portları (7880-7900 ve ilgili TURN portları) Node-1 firewall'unda açık tutulur.

### Avantajlar

| Kazanım | Açıklama |
|---|---|
| **Saldırı yüzeyi azalır** | Node-1'in public IP'si gizlenebilir; sadece LiveKit UDP portları ve Tailscale açık |
| **SSL CPU yükü dağıtılır** | TLS handshake Node-2'de yapılır |
| **DDoS filtresi** | Node-2 ilk barikat — SYN flood vb. Node-1'e ulaşmadan önce fail2ban/rate-limit'e çarpar |
| **Node-1 bant genişliği korunur** | Node-1'in 1.94 Gbps'i LiveKit + iç trafik için ayrılır |
| **Bağımsız güncelleme** | Node-1 restart'ta Node-2 502 dönebilir, ama yapı korunur |

### Dezavantajlar ve Riskler

| Risk | Ağırlık | Yönetim |
|---|---|---|
| **Ekstra gecikme** | Orta | Frankfurt↔Nürnberg ~10-15ms RTT; API için +20-30ms — mobil için kabul edilebilir |
| **Node-2 SPOF** | Yüksek | Node-2 düşerse tüm trafik durur. Mitigation: Node-1 nginx'i fallback DNS ile tutmak |
| **WS proxy yapılandırması** | Düşük | nginx'e `upgrade` header'ları + uzun `proxy_read_timeout` gerekli |
| **Let's Encrypt sertifika yönetimi** | Düşük | Node-2'de Certbot; Node-1'de artık sertifika gerekmez |

---

## 4. Hangi Servisler Nerede?

| Servis | Node-1 (OVH) | Node-2 (Netcup) | Notlar |
|---|---|---|---|
| PostgreSQL | ✅ | ❌ | Taşınamaz — NVMe, RAM gerekli |
| Redis | ✅ | ❌ | Tüm workers buna bağlı |
| MinIO | ✅ | ❌ | 98 GB disk gerekli |
| ClickHouse | ✅ | ❌ | RAM yoğun |
| LiveKit | ✅ | ❌ | UDP media; 1.94 Gbps gerekli |
| FastAPI (prod) | ✅ | ❌ | Tüm bağımlılıklar Node-1'de |
| FastAPI (staging) | ✅ | ❌ | Aynı nedenle |
| ARQ Workers | ✅ | ❌ | Redis'e doğrudan erişim gerekli |
| nginx (public) | ❌ → iç | ✅ | Node-1 nginx iç iletişime döner |
| Tailscale | ✅ | ✅ | Her iki node'da |
| Prometheus scrape | ✅ | Node-2'yi de izleyecek | |
| Grafana | ✅ | Node-2 proxy ile erişim | grafana.teqlif.com |
| Loki + Promtail | ✅ | Node-2 log'ları da gönderir | |
| fail2ban | ✅ | ✅ | Her iki node'da bağımsız |

---

## 5. Kod Değişikliği Gereksinimi

**Neredeyse sıfır.** Mevcut mimari bu geçişe hazır:

- `settings.redis_url` → Node-1 localhost'ta kalır, değişmez
- `settings.database_url` → Node-1 localhost'ta kalır, değişmez
- `settings.minio_dm_external_url` → zaten dış domain kullanıyor, değişmez
- `ws_manager` → Redis Stream fan-out zaten multi-node için tasarlandı
- CORS → `settings.site_url` tek domain, Node-2 IP değişimi CORS'u etkilemez

**Tek yapılandırma değişikliği:** Node-2'nin Tailscale IP'si üzerinden Node-1'e ulaşabilmesi için `.env`'de herhangi bir değişiklik yok — Node-1 üzerindeki servisler `127.0.0.1`'i dinlemeye devam eder, sadece Node-2'den gelen Tailscale IP'sine izin verilir.

---

## 6. Uygulama Adımları

### Adım 1 — Tailscale Kurulumu (Sıfır downtime)
```bash
# Her iki node'da
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --advertise-routes=...

# Bağlantı testi
ping node1-tailscale-ip
```

### Adım 2 — Node-2 Nginx Yapılandırması
```nginx
# /etc/nginx/sites-enabled/teqlif.conf (Node-2)

upstream node1_api {
    server <NODE1_TAILSCALE_IP>:8000;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name teqlif.com www.teqlif.com;

    # SSL — Let's Encrypt (Node-2'de Certbot)
    ssl_certificate /etc/letsencrypt/live/teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/teqlif.com/privkey.pem;

    # API + WebSocket
    location / {
        proxy_pass http://node1_api;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # WebSocket geçişi için zorunlu
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # WS bağlantılarını uzun tutmak için
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Uploads — büyük dosyalar için buffer ayarları
    location /uploads/ {
        proxy_pass http://node1_api;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
```

### Adım 3 — Node-1 Firewall Sertleştirme
```bash
# Node-1'de (OVH), HTTP/HTTPS sadece Node-2 Tailscale IP'sinden
ufw allow from <NODE2_TAILSCALE_IP> to any port 80
ufw allow from <NODE2_TAILSCALE_IP> to any port 8000

# LiveKit UDP portları herkese açık kalmaya devam eder
ufw allow 7880/tcp   # LiveKit HTTP
ufw allow 7881/tcp   # LiveKit TURN/TLS
ufw allow 50000:60000/udp  # WebRTC media

# SSH — Tailscale üzerinden veya kısıtlı IP
```

### Adım 4 — DNS Değişikliği
- `teqlif.com` A record → Node-2 public IP
- Staging → Node-2 üzerinden aynı yapıyla

### Adım 5 — Doğrulama
- [ ] API endpoint'leri çalışıyor
- [ ] WebSocket bağlantıları (DM, bildirim, chat) kurulabiliyor
- [ ] Sesli/görüntülü arama WebRTC ICE başarılı (LiveKit)
- [ ] `/uploads/` dosyaları erişilebilir
- [ ] MinIO presigned DM URL'leri çalışıyor
- [ ] Grafana → Node-2 proxy üzerinden erişilebilir

---

## 7. İzleme — Node-2 Eklenmesi

```yaml
# Node-1 Prometheus scrape_configs'e ek
- job_name: node2
  static_configs:
    - targets: ['<NODE2_TAILSCALE_IP>:9100']  # node_exporter
  labels:
    node: node2
```

Node-2'de `node_exporter` + `promtail` kurulur, log'lar Node-1 Loki'ye gönderilir.

---

## 8. Açık Sorular (Olgunlaştırılacak)

1. **Node-2 SPOF** — Node-2 düşünce kullanıcılar etkilenmesin diye nasıl bir fallback mekanizması kurulur? (DNS TTL kısaltma + Node-1 nginx fallback DNS?)

2. **Upload büyük dosyaları Node-2 üzerinden mi geçsin?** — Video yükleme (MB boyutunda) Tailscale tünelinden geçmek zorunda; bu tünel bant genişliğini etkiler mi? Alternatif: `uploads.teqlif.com` subdomain'ini Node-1'e doğrudan yönlendirmek.

3. **Nginx microcaching Node-2'de** — Feed ve listing API yanıtları için Node-2'de 1-5 saniyelik mikro cache kurulabilir; sık değişen veriler (WS, chat) cache'e alınmaz. Bu Node-1 yükünü ciddi ölçüde azaltır.

4. **Gelecek: FastAPI replika Node-2'de** — Node-2 RAM'i şu an yetmez (1.9 GB). Daha büyük bir plan için Node-2 upgrade'i veya Node-3 eklenmesi gerekir.

---

## 9. Sonraki Fazlar (V2.0+)

| Faz | Ne | Ne Zaman |
|---|---|---|
| V1.1 | Node-2'de nginx microcaching | Node-1 CPU %70+ sürekli ise |
| V2.0 | PostgreSQL streaming read replica (Node-2 veya Node-3) | Okuma sorguları yavaşlarsa |
| V2.1 | FastAPI replika node'u (Node-3, daha büyük RAM) | API yanıt süresi bozulursa |
| V2.2 | Redis Sentinel / Replication | Redis SPOF kabul edilemez hale gelirse |
| V3.0 | MinIO distributed mode | Depolama limiti yaklaşırsa |
