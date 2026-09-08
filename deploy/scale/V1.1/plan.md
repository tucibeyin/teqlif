# Teqlif Scale V1.1 — Plan

> **Hedef:** V1.0 üzerine 4 operasyonel iyileştirme — gateway nginx güçlendirme, microcaching, node1 cache header düzeltmesi, Alertmanager.  
> **Ön koşul:** V1.0 aktif ve stabil (2026-09-07 itibariyle).

---

## Değişiklik 1 — Staging Server Block Güçlendirme (gateway nginx)

**Sorun:** `staging.teqlif.com` server block'unda rate limiting ve security header yok. Production ile tutarsız.

**Çözüm:** Production block'tan rate limiting (`limit_req zone=api`) ve security header setini staging'e kopyala.

**Etki:** Sadece gateway nginx reload — sıfır downtime.

**Not:** `client_max_body_size 100M` staging'de zaten var (upload test için gerekli). Rate limiting biraz gevşek tutulabilir — staging'e bağlanan cihaz sayısı az.

---

## Değişiklik 2 — uploads.teqlif.com Cache-Control Düzeltmesi (node1 nginx)

**Sorun:** node1'deki `uploads.teqlif.com` nginx config'inde `Cache-Control: public, no-transform` yazıyor. Gateway fallback'te (`/uploads/`) zaten `immutable` var.

**Çözüm:** `no-transform` → `public, max-age=31536000, immutable` — V1.0'da gateway fallback'e uygulandı, node1'deki asıl config'e de uygulanacak.

**Neden önemli:** `uploads.teqlif.com` DNS Only → node1 direkt → Cloudflare CDN bu yanıtı önbelleğe alır. `immutable` ile Cloudflare sertifika süresi dolmadan revalidation yapmaz; CDN cache hit oranı artar, node1 → MinIO yükü azalır.

**Etki:** node1 nginx reload — sıfır downtime.

---

## Değişiklik 3 — nginx Microcaching (gateway)

**Sorun:** Her API isteği gateway → WireGuard → node1 zincirinden geçiyor. Burst trafikte (örn. canlı yayın açıldığında aynı listing'e onlarca istek) node1 gereksiz yük alıyor.

**Çözüm:** Gateway nginx'te `proxy_cache_path` tanımla, seçili public GET endpointleri için 5 saniyelik microcache uygula.

### Cache stratejisi

**Scope:** Yalnızca `Authorization` header'ı olmayan veya açıkça public olan GET istekleri.

**Cache key:** `$request_method$host$request_uri` (query string dahil, cookie/auth hariç) — sadece genel public endpoint'ler cachele.

**Hedef endpointler (public, kullanıcı-spesifik değil):**

| Path pattern | TTL | Gerekçe |
|---|---|---|
| `GET /api/listings*` | 5s | İlan listesi — sık değişmez, yüksek trafik |
| `GET /api/users/*/public` | 10s | Public profil — nadiren değişir |
| `GET /api/categories*` | 60s | Kategori listesi — çok nadiren değişir |

**Cache bypass (asla cache'lenmeyen):**
- `POST`, `PUT`, `PATCH`, `DELETE` — yazma işlemleri
- `/api/auth*` — kimlik doğrulama
- `/api/chat*` — WebSocket
- `*ws$` — WebSocket
- `Cache-Control: no-cache` header'ı olan istekler

**Cache zone konfigürasyonu:**
```nginx
# http block içine (nginx-http-zones.conf)
proxy_cache_path /var/cache/nginx/teqlif
    levels=1:2
    keys_zone=teqlif_cache:10m
    max_size=256m
    inactive=60s
    use_temp_path=off;
```

**Neden 256 MB:** gateway'in 2 GB RAM'i var. 256 MB cache zone güvenli.  
**Neden 5s:** Bir kullanıcı sayfayı yenilese bile stale veri görmez; aynı anda 100 istek geldiğinde 99'u cache'ten karşılanır.

**Etki:** gateway nginx reload — sıfır downtime.

---

## Değişiklik 4 — Alertmanager (gateway)

**Sorun:** Prometheus veri topluyor ama uyarı mekanizması yok. node1 çökerse, RAM/disk doluysa, servis duruyorsa bildirim gelmiyor.

**Çözüm:** Alertmanager binary'sini gateway'e kur, Prometheus'a alert rules ekle, bildirim kanalı yapılandır.

### Alert kuralları (Prometheus rules.yml)

| Alert | Koşul | Severity |
|---|---|---|
| `NodeDown` | `up == 0` (node1 veya gateway) | critical |
| `HighMemory` | node1 RAM kullanımı > %85 | warning |
| `DiskSpaceLow` | node1 disk kullanımı > %80 | warning |
| `ServiceDown` | FastAPI 8000 portu yanıt vermiyor | critical |
| `HighSwapUsage` | swap kullanımı > %50 | warning |

### Bildirim kanalı

İki seçenek:
- **Email (SMTP):** Basit, ek bağımlılık yok.
- **Webhook (Discord/Slack/Telegram):** Daha hızlı görünürlük, ücretsiz.

**Öneri: Webhook** — email SMTP konfigürasyonu gerektirir, webhook URL bir satır.

### Bileşenler (gateway)
- `alertmanager` binary → `/usr/local/bin/alertmanager`
- `/etc/alertmanager/alertmanager.yml` — receiver config
- `alertmanager.service` → systemd
- `/etc/prometheus/rules/teqlif.yml` — alert kuralları
- `prometheus.yml`'e `rule_files` ve `alerting` bloğu eklenir

**Etki:** gateway'de yeni servis (`alertmanager.service`). Prometheus restart gerekir.

---

## Uygulama Sırası

```
Adım 1 → Staging block güçlendirme   (gateway nginx, düşük risk)
Adım 2 → uploads.teqlif.com immutable (node1 nginx, düşük risk)
Adım 3 → nginx microcaching           (gateway nginx, orta risk)
Adım 4 → Alertmanager                 (yeni servis, yüksek risk)
```

Risk artan sırayla — her adım bağımsız, bir öncekinin başarısı şart değil.
