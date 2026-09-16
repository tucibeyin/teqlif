# Teqlif Scale V1.4 — Altyapı ve Kaynak Dizinleri (Resources)

Bu dizin, V1.4 (Core-Edge) mimarisine ait tüm sunucu yapılandırmalarının (scripts, systemd servisleri, .env şablonları ve tuning ayarları) yegane doğruluk kaynağıdır (Single Source of Truth). Sistem, eski V1.3 dizinine (`deploy/scale/resources`) hiçbir şekilde bağımlı değildir; kendi evrensel ve jenerik `REPO` bulma mantığıyla çalışır.

---

## 0. Yeni VPS — Ortak İlk Hazırlık

İster yeni bir Core (Node5) ister yeni bir Edge (Node4) sunucusu ayağa kaldırılıyor olsun, sunucuda herhangi bir `bootstrap_*.sh` betiği çalıştırılmadan önce aşağıdaki adımlar **root yetkisiyle** manuel olarak uygulanmalıdır.

### Adım 1: Kullanıcı Oluşturma ve Yetkilendirme
Sistemin tüm süreçleri güvenlik gereği root olmayan `tucibeyin` kullanıcısı üzerinden yürüyecektir.

```bash
# tucibeyin kullanıcısını oluştur ve sudo grubuna ekle
adduser --gecos "" tucibeyin
usermod -aG sudo tucibeyin

# SSH dizinini hazırla
mkdir -p /home/tucibeyin/.ssh
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
chmod 700 /home/tucibeyin/.ssh
```

### Adım 2: SSH Anahtar Erişimi
Sunucu sağlayıcınız şifreli root girişi veriyorsa, lokal bilgisayarınızdan kendi anahtarınızı yeni sunucuya atamanız gerekir.

```bash
# Lokal Mac cihazınızda çalıştırın:
ssh-copy-id -i ~/.ssh/id_ed25519.pub tucibeyin@<YENI_IP>
```

> **Not:** Şifresiz ve pratik erişim için lokal cihazınızın `~/.ssh/config` dosyasına şu bloğu ekleyebilirsiniz:
> ```
> Host teqlif-node5
>     HostName <YENI_IP>
>     User tucibeyin
>     IdentityFile ~/.ssh/id_ed25519
>     ServerAliveInterval 60
> ```

### Adım 3: Hostname ve Yerel Çözümleme
VPS'e mimarideki rolüne uygun (`node4`, `node5` vb.) ismi verin:

```bash
sudo hostnamectl set-hostname node5
echo "127.0.1.1 node5" | sudo tee -a /etc/hosts
```

### Adım 4: Temel Paketler, Git Yetkilendirmesi ve Repo (Pull/Push)
V1.4 mimarisi jenerik path mantığı kullanır ve repo kök dizininin `/var/www/teqlif.com` olduğunu varsayar. Düğümün (node) rahatça `git pull` ve `git push` yapabilmesi için SSH tabanlı Github yetkilendirmesi (Deploy Key) kullanılacaktır.

```bash
# Gerekli temel paketleri yükle
sudo apt update && sudo apt install -y git btop curl wget

# Kök repo dizinini oluştur ve yetkilendir
sudo mkdir -p /var/www/teqlif.com
sudo chown -R tucibeyin:tucibeyin /var/www/teqlif.com

# tucibeyin kullanıcısına geç
su - tucibeyin

# 1. Github için özel SSH anahtarı üret
ssh-keygen -t ed25519 -C "tucibeyin@gmail.com" -f ~/.ssh/github_key -N ""

# 2. Github SSH bağlantısını otomatikleştirmek için config oluştur
cat << 'EOF' >> ~/.ssh/config
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_key
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config

# 3. Üretilen açık anahtarı (public key) ekrana yazdır:
cat ~/.ssh/github_key.pub
```

> **ÖNEMLİ (Github Ayarı):** Yukarıdaki komutun ekrana yazdırdığı `ssh-ed25519...` ile başlayan anahtarı kopyalayın. Github deponuza gidin -> **Settings** -> **Deploy Keys** sekmesinden **"Add deploy key"** butonuna basın. Anahtarı yapıştırın ve **"Allow write access"** (Yazma izni ver) kutucuğunu İŞARETLEYİN (Böylece Node üzerinden push yapabilirsiniz).

Anahtarı Github'a ekledikten sonra repoyu SSH ile klonlayabilirsiniz:
```bash
# Repoyu SSH protokolüyle indir (Böylece pull/push şifre sormaz)
git clone git@github.com:tucibeyin/teqlif.git /var/www/teqlif.com

# Git kullanıcı bilgilerinizi ayarlayın (Tüm node'larda standart tucibeyin hesabı kullanılır)
git config --global user.name "tucibeyin"
git config --global user.email "tucibeyin@gmail.com"
```

### Adım 5: Sunucu Kimliği (MOTD)
Sunucuya SSH ile her girildiğinde rolünü hatırlatması için karşılama ekranını güncelleyin:

```bash
# root olarak veya sudo ile:
sudo tee /etc/motd << 'EOF'

=========================================
 🖥️  NODE5 (Örnek: Core - Orchestrator & DB)
 📍  Provider : ZAP-Hosting
 🌐  Public IP: <IP>
 🎯  Roles    : FastAPI, PostgreSQL, ClickHouse, Redis Core
=========================================

EOF
```

---
> **ÖNEMLİ:** Bu 5 adım tamamlandıktan sonra, sunucunun asıl altyapısını kurmak için ilgili V1.4 resources klasörüne (`cd /var/www/teqlif.com/deploy/scale/V1.4/<node>/resources`) gidip `bootstrap_<node>.sh` dosyasını çalıştırabilirsiniz.
