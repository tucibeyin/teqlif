# deploy/scale/resources — Tek Kaynak Nokta

Bu dizin tüm node'lar için `.env` şablonları, `requirements` dosyaları ve
kurulum/yönetim scriptlerini içerir. Alt dizinlere ayrılmıştır; path'ler
versiyondan bağımsız olarak **hiç değişmez**.

```
resources/
├── node1/
│   ├── .env.production              ← teqlif, teqlif-worker, minio
│   ├── node1_production_requirements.txt
│   ├── bootstrap_node1.sh
│   ├── node1_services.sh
│   └── apply_pg_tuning.sh
├── node2/
│   ├── .env.production              ← teqlif-ai-proxy, cf-failover
│   ├── node2_production_requirements.txt
│   ├── bootstrap_node2.sh
│   └── node2_services.sh
├── node3/
│   ├── .env.production              ← teqlif-ai-proxy (node3), alertmanager
│   ├── .env.staging                 ← teqlif-staging, teqlif-worker-staging, minio (staging)
│   ├── node3_production_requirements.txt
│   ├── node3_staging_requirements.txt
│   ├── bootstrap_node3.sh
│   └── node3_services.sh
└── gateway/
    ├── bootstrap_gateway.sh
    ├── gateway_services.sh
    └── certbot_gateway.sh
```

---

## Dosya isimlendirme kuralı

Her node altında **en fazla 2 env dosyası**: `.env.production` ve `.env.staging` (staging varsa).  
Tüm servisler EnvironmentFile olarak doğrudan bu path'leri okur — `backend/.env` gibi ara kopya kullanılmaz.

| Tür          | Şablon                            | Örnek                           |
|--------------|-----------------------------------|---------------------------------|
| requirements | `{node}_{ortam}_requirements.txt` | `node1_production_requirements.txt` |
| .env         | `.env.{ortam}`                    | `node1/.env.production`         |
| scripts      | `{eylem}_{node}.sh`               | `bootstrap_node1.sh`            |

## Mevcut .env dosyaları ve servis eşleşmeleri

| Dosya | Okuyan servisler | Açıklama |
|-------|-----------------|----------|
| `node1/.env.production` | teqlif, teqlif-worker, teqlif-worker-critical, minio | node1 production app + MinIO |
| `node2/.env.production` | teqlif-ai-proxy, cf-failover | AI proxy + Cloudflare failover |
| `node3/.env.production` | teqlif-ai-proxy (node3), alertmanager | AI proxy secondary + monitoring |
| `node3/.env.staging`    | teqlif-staging, teqlif-worker-staging, teqlif-worker-critical-staging, minio (staging) | Staging app + MinIO |

---

## Systemd EnvironmentFile path'leri (Scale V1.3)

| Servis | Node | EnvironmentFile |
|--------|------|-----------------|
| teqlif.service | node1 | `.../resources/node1/.env.production` |
| teqlif-worker.service | node1 | `.../resources/node1/.env.production` |
| teqlif-worker-critical.service | node1 | `.../resources/node1/.env.production` |
| minio.service | node1 | `.../resources/node1/.env.production` |
| teqlif-ai-proxy.service | node2 | `.../resources/node2/.env.production` |
| cf-failover.service | node2 | `.../resources/node2/.env.production` |
| teqlif-ai-proxy.service | node3 | `.../resources/node3/.env.production` |
| alertmanager.service | node3 | `.../resources/node3/.env.production` |
| teqlif-staging.service | node3 | `.../resources/node3/.env.staging` |
| teqlif-worker-staging.service | node3 | `.../resources/node3/.env.staging` |
| teqlif-worker-critical-staging.service | node3 | `.../resources/node3/.env.staging` |
| minio.service | node3 | `.../resources/node3/.env.staging` |

---

## 0. Yeni VPS — Ortak İlk Hazırlık

Her yeni VPS'te node kurulumundan önce aşağıdaki adımlar **root olarak** çalıştırılır.

### Kullanıcı oluştur

```bash
# tucibeyin kullanıcısını oluştur ve sudo grubuna ekle
adduser --gecos "" tucibeyin
usermod -aG sudo tucibeyin

# SSH dizinini hazırla
mkdir -p /home/tucibeyin/.ssh
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
chmod 700 /home/tucibeyin/.ssh
```

> **Not:** Bazı sağlayıcılar (Zap-Hosting gibi) root için şifre kullanır, SSH key kullanmaz.
> Bu durumda `cp /root/.ssh/authorized_keys` işe yaramaz — aşağıdaki adımla lokal key eklenir.

### SSH key ekle (lokal makinadan — bir kez şifre girerek)

```bash
# Lokal Mac'te çalıştır:
ssh-copy-id -i ~/.ssh/id_ed25519.pub tucibeyin@<IP>
```

### SSH alias ekle (lokal makinada ~/.ssh/config)

```
Host teqlif-<hostname>
    HostName <IP>
    User tucibeyin
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

Bundan sonra `ssh teqlif-<hostname>` ile şifresiz bağlanılır.

### Makine adını ayarla

VPS amacına göre hostname ver (`node1`, `node2`, `node3`, `gateway` veya başka bir isim):

```bash
sudo hostnamectl set-hostname <hostname>
echo "127.0.1.1 <hostname>" | sudo tee -a /etc/hosts
```

### Temel araçları yükle

```bash
sudo apt update && sudo apt install -y git btop curl wget

# Repo dizinini oluştur ve klonla
mkdir -p /var/www/teqlif.com
git clone https://github.com/tucibeyin/teqlif.git /var/www/teqlif.com
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

> **Not:** Repo private ise git clone için HTTPS personal access token kullan:
> `git clone https://<token>@github.com/tucibeyin/teqlif.git /var/www/teqlif.com`
> Token aldıktan sonra remote URL'i temizle: `git remote set-url origin https://github.com/tucibeyin/teqlif.git`

### Giriş ekranı (MOTD) ayarla

```bash
sudo tee /etc/motd << 'EOF'

=========================================
 🖥️  <HOSTNAME> (<Rol>)
 📍  Provider : <Sağlayıcı>
 🌐  Public IP: <IP>
 📅  Purchase : <Tarih>
 🎯  Roles    : <Rol 1>
                <Rol 2>
=========================================

EOF
```

Bundan sonra **tucibeyin** kullanıcısıyla bağlan ve ilgili node kurulumuna geç.

---

## node1 (OVHcloud Limburg) — İlk Kurulum

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
