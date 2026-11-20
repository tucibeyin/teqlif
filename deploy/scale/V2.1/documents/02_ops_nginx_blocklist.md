# 02 — Nginx Agresif IP Blok Listesi & Dotfile Sertleştirme (Ops)

> **Durum:** Aktif — `work_003` kapsamında devreye alındı.
> **Etki alanı:** `node1` (prod: teqlif.com, www, api.teqlif.com, uploads.teqlif.com) ve `node5` (staging aynası).
> **Tetikleyici:** 2026-11-20 12:23 UTC'de `35.240.59.25` (GCP) IP'sinden ~30 adet dotfile/config sızıntı taraması (`.config/claude/config.json`, `.vscode/sftp.json`, `.m2/settings.xml`, `.vault_pass.txt`, `.ansible/vault_pass.txt`, `.gradle/gradle.properties` vb.). Tüm istekler 403 ile kesildi; **güvenlik ihlali yok**, ancak `error_log` `[error]` kayıtlarıyla doldu ve gerçek hataların görünürlüğü azaldı.

---

## 1. Mekanizma

### 1.1 `00-blocklist.conf` (geo değişkeni)

`conf.d/` dizini **alfabetik** olarak `http` context'ine yüklenir. `00-` öneki sayesinde `geo $teqlif_blocked_ip` değişkeni, `teqlif.conf` / `minio.conf` / `teqlif-staging.conf` içindeki `server` bloklarından **önce** tanımlanır.

```nginx
geo $teqlif_blocked_ip {
    default 0;
    35.240.59.25    1;   # GCP — dotfile taraması (2026-11-20)
}
```

- Dosya konumu (repo → canlı):
  - `deploy/scale/V2.1/node1/resources/nginx/conf.d/00-blocklist.conf` → `node1:/etc/nginx/conf.d/00-blocklist.conf`
  - `deploy/scale/V2.1/node5/resources/nginx/conf.d/00-blocklist.conf` → `node5:/etc/nginx/conf.d/00-blocklist.conf`
- Gerçek IP çözümü: Cloudflare arkalı hostlarda (`teqlif.com`, `api.teqlif.com`, `staging.*`, `api-staging.*`) nginx.conf'taki `set_real_ip_from` + `CF-Connecting-IP` başlığı `$remote_addr`'i gerçek istemci IP'sine çevirir. `uploads.*` ve `live-staging.*` DNS-only olduğundan `$remote_addr` zaten istemci IP'sidir. Her iki senaryoda eşleşme doğrudur.

### 1.2 Server bloklarındaki guard

Her ilgili `server` bloğunda tek satır:

```nginx
if ($teqlif_blocked_ip) { return 403; }
```

- **Neden `deny` değil `return`?** `deny` modülü engellenen isteği `error_log`'a `[error] access forbidden by rule` olarak yazar. `return 403` yalnızca `access_log`'a durum kodu düşer. Amaç: gerçek hataları gizleyen alarm gürültüsünü kesmek.
- `if` + `return` server context'te güvenlidir (rewrite fazında, location seçiminden önce çalışır); `if` içinde `proxy_pass` gibi güvenli olmayan direktif kullanılmamıştır.

### 1.3 Dotfile kuralı sertleştirmesi

| | Önce | Sonra |
|---|---|---|
| teqlif.com / www (node1) | `location ~ /\. { deny all; }` | `location ~ /\. { return 404; }` |
| staging.teqlif.com (node5) | **kural yoktu** | `location ~ /\. { return 404; }` |

- `return 404` → `error_log` temiz kalır, istekler `access_log`'da 404 olarak denetlenebilir.
- `/.well-known/` etkilenmez: `location ^~ /.well-known/` prefix (`^~`) eşleşmesi regex location'dan önce değerlendirilir (ACME, Android App Links, Apple Universal Links korunur).
- `api.teqlif.com` / `api-staging.teqlif.com` bloklarında statik kök (`root`) yok; dotfile kuralı gerekmez, yalnızca IP guard eklendi.

---

## 2. Dağıtım

Değişiklikler **elle kopyalanmaz**. `teqlif-restart` içindeki `sync_nginx()` akışı kullanılır:

```
repo: <node>/resources/nginx/conf.d/*.conf
   → diff
   → değişen dosyalar /etc/nginx/conf.d/ altına kopyalanır (mevcut dosyalar .bak'a alınır)
   → nginx -t
        ├─ başarılı → systemctl reload nginx
        └─ başarısız → .bak'tan otomatik geri dönüş, reload İPTAL   (fail-safe)
```

**Sıra (zorunlu):**
1. `node5` (staging): `sudo teqlif-restart` → `nginx -t` geçmeli, ardından davranış doğrulanır.
2. Staging doğrulaması temizse `node1` (prod): `sudo teqlif-restart`.

> ⚠️ `sync_nginx()` **ana `/etc/nginx/nginx.conf` dosyasını senkronize etmez.** Bu yüzden bu iş kapsamında global `error_log` seviyesi **değiştirilmedi** (o yaklaşım GitOps dışı kalır ve gerçek hataları da susturur). Gürültü kaynağı, `deny → return` dönüşümüyle kaynak noktasında giderildi.

---

## 3. Doğrulama

### 3.1 Staging (node5)

```bash
# 1) Config geçerliliği
sudo nginx -t

# 2) Blok listesi devrede mi? (403 beklenir)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve staging.teqlif.com:443:10.10.0.5 \
  -H 'CF-Connecting-IP: 35.240.59.25' \
  https://staging.teqlif.com/.env

# 3) Meşru trafik etkilenmiyor mu? (200/302 beklenir)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve staging.teqlif.com:443:10.10.0.5 \
  -H 'CF-Connecting-IP: 88.240.1.10' \
  https://staging.teqlif.com/

# 4) Dotfile → 404
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve staging.teqlif.com:443:10.10.0.5 \
  -H 'CF-Connecting-IP: 88.240.1.10' \
  https://staging.teqlif.com/.env

# 5) .well-known regresyon kontrolü (404 OLMAMALI)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve staging.teqlif.com:443:10.10.0.5 \
  https://staging.teqlif.com/.well-known/assetlinks.json
```

### 3.2 Prod (node1)

```bash
# 403 (bloklu IP)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve teqlif.com:443:10.10.0.1 \
  -H 'CF-Connecting-IP: 35.240.59.25' \
  https://teqlif.com/.git/config

# 200/302 (meşru IP — regresyon yok)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve teqlif.com:443:10.10.0.1 \
  -H 'CF-Connecting-IP: 88.240.1.10' \
  https://teqlif.com/

# uploads (DNS Only) — bloklu IP doğrudan $remote_addr üzerinden
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve uploads.teqlif.com:443:10.10.0.1 \
  https://uploads.teqlif.com/
```

### 3.3 Log doğrulaması

```bash
# error_log'da artık "access forbidden by rule" GÖRÜLMEMELİ
sudo tail -n 200 /var/log/nginx/error.log | grep -c 'access forbidden by rule'   # → 0

# 403'ler access_log'da bloklu IP ile görünür
sudo grep '35.240.59.25' /var/log/nginx/access.log | tail -n 5
```

Loki tarafı:
```logql
{job="nginx", node="node1"} |~ "\" 403 " |~ "35\\.240\\.59\\.25"
{node="node1", unit="nginx"} |~ "access forbidden by rule"    # → boş olmalı
```

### 3.4 Regresyon kontrol listesi

- [ ] `nginx -t` her iki node'da başarılı
- [ ] `teqlif.com`, `www.teqlif.com`, `api.teqlif.com` → 200/302, frontend ve API normal
- [ ] `uploads.teqlif.com` presigned PUT/GET akışı çalışıyor (video upload)
- [ ] WebSocket rotası (`/api/chat/...ws`) bağlanıyor, `proxy_read_timeout 3600s` korunmuş
- [ ] `/.well-known/` 404 dönmüyor
- [ ] `error_log`'da `access forbidden by rule` sayısı 0
- [ ] API 5xx sayısı değişmedi (`{job="nginx", node="node1"} |~ "\" 5[0-9][0-9] "` → 0)

---

## 4. Operasyon: IP ekleme / kaldırma

### Ekleme
1. İlgili node'un `00-blocklist.conf` dosyasına satır ekle:
   ```nginx
   198.51.100.42    1;   # kısa açıklama (YYYY-MM-DD)
   ```
2. Commit + push.
3. İlgili node'da `sudo teqlif-restart`.
4. Doğrula: `curl` → 403 ve `error_log` temiz.

### Kaldırma
- Satırı sil (veya değeri `0` yap) → commit + push → `sudo teqlif-restart`.

### Acil durum (repo beklemeden, yalnızca prod kesintisi varsa)
```bash
sudo sed -i 's/^\( *\)35\.240\.59\.25 *1;/\1# &/' /etc/nginx/conf.d/00-blocklist.conf
sudo nginx -t && sudo systemctl reload nginx
```
> Ardından **aynı değişikliği repo'ya commit et.** Sonraki `sync_nginx()` canlı dosyanın üzerine repo içeriğini yazar; repo güncellenmezse acil müdahale geri alınır.

---

## 5. Geri alma (tam)

```bash
cd /opt/teqlif  # veya repo yolu
git revert <commit>
sudo teqlif-restart
```

Yalnızca dotfile davranışını geri almak için `location ~ /\.` içindeki `return 404;` satırı `deny all;` yapılır — tek satırlık değişiklik.

---

## 6. Cloudflare WAF (tamamlayıcı, manuel adım)

Nginx guard'ı **edge'de değil origin'de** çalışır; istek hâlâ Cloudflare'e ulaşıp origin'e proxy edilir. Tam koruma için Cloudflare panelinde **origin'e hiç ulaşmayacak** ikinci katman önerilir:

1. **Security → WAF → Custom rules** → yeni kural:
   - Expression: `(ip.src eq 35.240.59.25)`
   - Action: **Block**
2. **Security → WAF → Managed rules** → Cloudflare Managed Ruleset açık olmalı (dotfile/config probe'larını imza bazlı yakalar).
3. Doğrulama: `curl -I https://teqlif.com/.env` dış ağdan → Cloudflare `403` + `cf-ray` başlığı; origin `access.log`'da **kayıt görülmemeli**.

> WAF kuralı eklenirse nginx tarafındaki IP satırı savunma derinliği (defense-in-depth) olarak kalabilir; zararı yoktur.

---

## 7. Loki `ratestore` notu (bu işin kapsamı dışı — izleme)

`nodeMonitor` (`10.10.0.99`) üzerindeki Loki'de 2026-11-20 12:17:14 UTC'de tek seferlik:

```
level=error msg="unable to get stream rates from ingester" ingester=10.10.0.99:9096 err="context deadline exceeded"
```

- **teqlif prod ile ilgisi yok.** Loki'nin kendi rate-store bileşeninin ingester'a ulaşamaması.
- Sonraki sorgular `status=200` ile tamamlandı (15279 satır tarandı). Tekrarlayan kesinti yok.
- Aksiyon: düşük öncelikli izleme. Sıklaşırsa nodeMonitor tarafında `-querier.ingester-streams-lookback`, `ratestore` timeout ve `10.10.0.99:9096` ağ gecikmesi incelenmeli.

---

## 8. Değişen dosyalar (work_003)

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V2.1/node1/resources/nginx/conf.d/00-blocklist.conf` | **YENİ** — `geo $teqlif_blocked_ip` + `35.240.59.25` |
| `deploy/scale/V2.1/node1/resources/nginx/conf.d/teqlif.conf` | teqlif.com/www + api guard; `deny all` → `return 404` |
| `deploy/scale/V2.1/node1/resources/nginx/conf.d/minio.conf` | uploads guard |
| `deploy/scale/V2.1/node5/resources/nginx/conf.d/00-blocklist.conf` | **YENİ** — staging aynası |
| `deploy/scale/V2.1/node5/resources/nginx/conf.d/teqlif-staging.conf` | 4 server bloğuna guard + staging'de eksik olan dotfile kuralı eklendi |
