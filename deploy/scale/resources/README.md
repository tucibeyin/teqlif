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
    ├── .env.gateway.production
    ├── bootstrap_gateway.sh
    ├── gateway_services.sh
    └── certbot_gateway.sh
```

---

## Dosya isimlendirme

| Tür          | Şablon                            | Örnek                                |
|--------------|-----------------------------------|--------------------------------------|
| requirements | `{node}_{ortam}_requirements.txt` | `node1_production_requirements.txt`  |
| .env         | `.env.{node}.{ortam}`             | `.env.node1.production`              |
| scripts      | `{eylem}_{node}.sh`               | `bootstrap_node1.sh`                 |

## Mevcut .env dosyaları

| Dosya | Servis | Açıklama |
|-------|--------|----------|
| `node1/.env.node1.production` | teqlif, teqlif-staging, teqlif-worker | node1 prod ortam değişkenleri |
| `node1/.env.node1.staging` | teqlif-staging | node1 staging ortam değişkenleri |
| `node2/.env.node2.production` | teqlif-ai-proxy | GROQ_API_KEY, GEMINI_API_KEY, NODE2_INTERNAL_TOKEN |
| `node2/.env.node2.cfFailover` | cf-failover | CF_ZONE_ID, CF_API_TOKEN |
| `gateway/.env.gateway.production` | alertmanager | TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID |

---

## Systemd EnvironmentFile path'leri

| Servis                   | EnvironmentFile                                                      |
|--------------------------|----------------------------------------------------------------------|
| teqlif.service           | `.../deploy/scale/resources/node1/.env.node1.production`             |
| teqlif-staging.service   | `.../deploy/scale/resources/node1/.env.node1.staging`                |
| teqlif-worker.service    | `.../deploy/scale/resources/node1/.env.node1.production`             |
| teqlif-ai-proxy.service  | `.../deploy/scale/resources/node2/.env.node2.production`             |
| cf-failover.service      | `.../deploy/scale/resources/node2/.env.node2.cfFailover`             |
| alertmanager.service     | `.../deploy/scale/resources/gateway/.env.gateway.production`         |

---

## 0. Yeni VPS — Ortak İlk Hazırlık

Her yeni VPS'te node kurulumundan önce aşağıdaki adımlar **root olarak** çalıştırılır.

### Kullanıcı oluştur

```bash
# tucibeyin kullanıcısını oluştur ve sudo grubuna ekle
adduser tucibeyin
usermod -aG sudo tucibeyin

# Root'un SSH authorized_keys'ini tucibeyin'e kopyala (mevcut SSH erişimi korunur)
mkdir -p /home/tucibeyin/.ssh
cp /root/.ssh/authorized_keys /home/tucibeyin/.ssh/
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
chmod 700 /home/tucibeyin/.ssh
chmod 600 /home/tucibeyin/.ssh/authorized_keys
```

### Makine adını ayarla

VPS amacına göre hostname ver (`node1`, `node2`, `gateway` veya başka bir isim):

```bash
hostnamectl set-hostname <hostname>
echo "127.0.1.1 <hostname>" >> /etc/hosts
```

### Git ve repo

```bash
apt update && apt install -y git

# Repo dizinini oluştur ve klonla
mkdir -p /var/www/teqlif.com
git clone https://github.com/tucibeyin/teqlif.git /var/www/teqlif.com
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

> **Not:** Repo private ise git clone için HTTPS personal access token kullan:
> `git clone https://<token>@github.com/tucibeyin/teqlif.git /var/www/teqlif.com`
> Token aldıktan sonra remote URL'i temizle: `git remote set-url origin https://github.com/tucibeyin/teqlif.git`

Bundan sonra **tucibeyin** kullanıcısıyla bağlan ve ilgili node kurulumuna geç.

---

## node1 (OVHcloud Frankfurt) — İlk Kurulum

**Ön koşul:** `/var/www/teqlif.com` repoya git clone edilmiş, `deploy/scale/V1.2/` mevcut.

```bash
cd /var/www/teqlif.com

# 1. .env şablonunu doldur (git pull sonrası boş gelir)
# chmod 600 bootstrap tarafından otomatik uygulanır
nano deploy/scale/resources/node1/.env.node1.production
nano deploy/scale/resources/node1/.env.node1.staging

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
# chmod 600 bootstrap tarafından otomatik uygulanır
nano deploy/scale/resources/node2/.env.node2.production
nano deploy/scale/resources/node2/.env.node2.cfFailover

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

# 1. .env şablonunu doldur
# chmod 600 bootstrap tarafından otomatik uygulanır
nano deploy/scale/resources/gateway/.env.gateway.production

# 2. Bootstrap çalıştır (idempotent)
bash deploy/scale/resources/gateway/bootstrap_gateway.sh

# 3. WireGuard (henüz kurulmadıysa)
sudo bash -c 'wg genkey | tee /etc/wireguard/gateway_private.key | wg pubkey > /etc/wireguard/gateway_public.key'
# wg0.conf oluştur (node1 + node2 peer'lar), sonra:
sudo systemctl enable --now wg-quick@wg0

# 4. Bootstrap'i tekrar çalıştır (node2 peer'ı ekler)
bash deploy/scale/resources/gateway/bootstrap_gateway.sh

# 5. SSL sertifikası al (DNS A kaydı gateway'e işaret etmeli)
bash deploy/scale/resources/gateway/certbot_gateway.sh

# 6. alertmanager.yml kopyala
sudo cp deploy/scale/V1.2/gateway/alertmanager.yml.template /etc/alertmanager/alertmanager.yml

# 7. Servisleri başlat
bash deploy/scale/resources/gateway/gateway_services.sh start

# 8. Durum kontrolü
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
