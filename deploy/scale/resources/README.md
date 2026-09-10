# deploy/scale/resources — Tek Kaynak Nokta

Bu dizin tüm node'lar için `.env` şablonları, `requirements` dosyaları ve
kurulum/yönetim scriptlerini içerir. Alt dizinlere ayrılmıştır; path'ler
versiyondan bağımsız olarak **hiç değişmez**.

```
resources/
├── node1/
│   ├── .env.node1.production
│   ├── .env.node1.staging
│   ├── node1_production_requirements.txt
│   ├── node1_staging_requirements.txt
│   ├── bootstrap_node1.sh
│   ├── node1_services.sh
│   └── apply_pg_tuning.sh
├── node2/
│   ├── .env.node2.production
│   ├── .env.node2.cfFailover
│   ├── node2_production_requirements.txt
│   ├── bootstrap_node2.sh
│   └── node2_services.sh
└── gateway/
    ├── bootstrap_gateway.sh
    ├── gateway_services.sh
    └── certbot_gateway.sh
```

---

## Dosya isimlendirme

| Tür          | Şablon                            | Örnek                              |
|--------------|-----------------------------------|------------------------------------|
| requirements | `{node}_{ortam}_requirements.txt` | `node1_production_requirements.txt` |
| .env         | `.env.{node}.{ortam}`             | `.env.node1.production`            |
| scripts      | `{eylem}_{node}.sh`               | `bootstrap_node1.sh`               |

---

## Systemd EnvironmentFile path'leri

| Servis                   | EnvironmentFile                                                      |
|--------------------------|----------------------------------------------------------------------|
| teqlif.service           | `.../deploy/scale/resources/node1/.env.node1.production`             |
| teqlif-staging.service   | `.../deploy/scale/resources/node1/.env.node1.staging`                |
| teqlif-worker.service    | `.../deploy/scale/resources/node1/.env.node1.production`             |
| teqlif-ai-proxy.service  | `.../deploy/scale/resources/node2/.env.node2.production`             |
| cf-failover.service      | `.../deploy/scale/resources/node2/.env.node2.cfFailover`             |

---

## node1 (OVHcloud Frankfurt) — İlk Kurulum

**Ön koşul:** `/var/www/teqlif.com` repoya git clone edilmiş, `deploy/scale/V1.2/` mevcut.

```bash
cd /var/www/teqlif.com

# 1. .env şablonunu doldur (git pull sonrası boş gelir)
nano deploy/scale/resources/node1/.env.node1.production
chmod 600 deploy/scale/resources/node1/.env.node1.production
chmod 600 deploy/scale/resources/node1/.env.node1.staging

# 2. Bootstrap çalıştır (idempotent — tekrar çalıştırmak güvenli)
bash deploy/scale/resources/node1/bootstrap_node1.sh

# 3. WireGuard (henüz kurulmadıysa)
sudo bash -c 'wg genkey | tee /etc/wireguard/node1_private.key | wg pubkey > /etc/wireguard/node1_public.key'
# wg0.conf oluştur, sonra:
sudo systemctl enable --now wg-quick@wg0

# 4. Bootstrap'i tekrar çalıştır (node2 peer'ı ekler)
bash deploy/scale/resources/node1/bootstrap_node1.sh

# 5. PostgreSQL tuning uygula
bash deploy/scale/resources/node1/apply_pg_tuning.sh

# 6. Servisleri başlat
bash deploy/scale/resources/node1/node1_services.sh start

# 7. Durum kontrolü
bash deploy/scale/resources/node1/node1_services.sh status
```

**Ayrıca kurulması gerekenler (script dışı):**
- PostgreSQL (apt), Redis, LiveKit, MinIO

---

## node2 (VPSHostingService.co Buffalo) — İlk Kurulum

**Ön koşul:** `/var/www/teqlif.com` repoya git clone edilmiş.

```bash
cd /var/www/teqlif.com

# 1. .env şablonlarını doldur
nano deploy/scale/resources/node2/.env.node2.production
nano deploy/scale/resources/node2/.env.node2.cfFailover
chmod 600 deploy/scale/resources/node2/.env.node2.production
chmod 600 deploy/scale/resources/node2/.env.node2.cfFailover

# 2. WireGuard key oluştur
sudo bash -c 'wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key'

# 3. Bootstrap çalıştır (idempotent)
bash deploy/scale/resources/node2/bootstrap_node2.sh
# → wg0.conf otomatik yazılır, wg-quick@wg0 başlatılır

# 4. Servisleri başlat
bash deploy/scale/resources/node2/node2_services.sh start

# 5. Durum kontrolü
bash deploy/scale/resources/node2/node2_services.sh status

# 6. cf-failover logunu izle
sudo journalctl -u cf-failover -f
```

---

## gateway (netcup Nürnberg) — İlk Kurulum

**Ön koşul:** `/var/www/teqlif.com` repoya git clone edilmiş, DNS A kayıtları gateway IP'sine işaret ediyor.

```bash
cd /var/www/teqlif.com

# 1. Bootstrap çalıştır (idempotent)
bash deploy/scale/resources/gateway/bootstrap_gateway.sh

# 2. WireGuard (henüz kurulmadıysa)
sudo bash -c 'wg genkey | tee /etc/wireguard/gateway_private.key | wg pubkey > /etc/wireguard/gateway_public.key'
# wg0.conf oluştur (node1 + node2 peer'lar), sonra:
sudo systemctl enable --now wg-quick@wg0

# 3. Bootstrap'i tekrar çalıştır (node2 peer'ı ekler)
bash deploy/scale/resources/gateway/bootstrap_gateway.sh

# 4. SSL sertifikası al (DNS A kaydı gateway'e işaret etmeli)
bash deploy/scale/resources/gateway/certbot_gateway.sh

# 5. Alertmanager'ı yapılandır
sudo nano /etc/alertmanager/alertmanager.yml
sudo nano /etc/alertmanager/alertmanager.env  # SLACK_WEBHOOK_URL

# 6. Servisleri başlat
bash deploy/scale/resources/gateway/gateway_services.sh start

# 7. Durum kontrolü
bash deploy/scale/resources/gateway/gateway_services.sh status
```

**Ayrıca kurulması gerekenler (script dışı):**
- Grafana (apt repo: `grafana-oss`)

---

## Rutin Güncelleme (tüm node'lar)

```bash
# node1
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

# node2
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy

# gateway
cd /var/www/teqlif.com && git pull
sudo systemctl reload nginx
sudo systemctl restart prometheus loki alertmanager
```

---

## Yeni ortam değişkeni eklenince

1. İlgili `resources/{node}/.env.{node}.{ortam}` dosyasına yeni satır ekle
2. `deploy/scale/V1.2/{node}/systemd/*.service` dosyasını kontrol et
3. Commit + push → tüm node'larda `git pull` yeterli, **path değişikliği yok**
