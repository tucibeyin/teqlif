# Teqlif Scale V2.0 — Yeni Node İlk Hazırlık

Her node için `02_plan.md` Faz adımlarına geçmeden önce tamamlanması gereken ortak hazırlık adımları. Tüm 11 node için geçerlidir; node'a özgü farklar ilgili adımda belirtilir.

**OS:** Debian 13 (trixie) — fresh install, migration yok, V1.x kalıntısı yok.

---

## Node Referans Tablosu

| Hostname | WG IP | Rol | Provider |
|----------|-------|-----|----------|
| gateway1 | 10.10.0.2 | Edge Proxy #1 | Netcup NUE |
| gateway2 | 10.10.0.9 | Edge Proxy #2 | DELUXHOST AMS |
| node1 | 10.10.0.1 | Stream #1 (LiveKit) | OVH FRA |
| node2 | 10.10.0.3 | AI Proxy | RackNerd BUF |
| node3 | 10.10.0.4 | Staging | ZAP VA |
| node4 | 10.10.0.6 | Stream #2 (LiveKit) | OVH FRA |
| node5 | 10.10.0.5 | Core #1 (Primary) | ZAP MUN |
| node6 | 10.10.0.7 | Core #2 (Standby) | DELUXHOST AMS |
| node7 | 10.10.0.8 | Storage #1 | DELUXHOST NL |
| node8 | 10.10.0.12 | Storage #2 | DELUXHOST NL |
| node9 | 10.10.0.13 | Backup + Monitor + ClickHouse | OVH LIM |

---

## Adım 1 — Kullanıcı ve Sudo

```bash
# root olarak:
adduser --gecos "" tucibeyin
usermod -aG sudo tucibeyin

mkdir -p /home/tucibeyin/.ssh
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
chmod 700 /home/tucibeyin/.ssh
```

---

## Adım 2 — SSH Erişimi

Lokal Mac'ten kendi anahtarını yeni node'a kopyala:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub tucibeyin@<NODE_IP>
```

`~/.ssh/config`'e eklersen şifresiz erişim sağlanır:

```
Host node5
    HostName <NODE_IP>
    User tucibeyin
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

---

## Adım 3 — Hostname

```bash
# Hostname'i node'un rolüne göre ayarla (gateway1, node5, node9 vb.):
sudo hostnamectl set-hostname <HOSTNAME>
echo "127.0.1.1 <HOSTNAME>" | sudo tee -a /etc/hosts
```

---

## Adım 4 — Temel Paketler + Git + Repo

```bash
sudo apt update && sudo apt install -y git btop curl wget

sudo mkdir -p /var/www/teqlif.com
sudo chown -R tucibeyin:tucibeyin /var/www/teqlif.com

su - tucibeyin

# GitHub deploy key oluştur
ssh-keygen -t ed25519 -C "tucibeyin@gmail.com" -f ~/.ssh/github_key -N ""

cat >> ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_key
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config

# Public key'i ekrana yazdır — GitHub'a eklenecek
cat ~/.ssh/github_key.pub
```

**GitHub:** Repo → Settings → Deploy Keys → Add deploy key → "Allow write access" işaretle.

```bash
git clone git@github.com:tucibeyin/teqlif.git /var/www/teqlif.com

git config --global user.name "tucibeyin"
git config --global user.email "tucibeyin@gmail.com"
```

---

## Adım 5 — MOTD

Her node'da SSH girişinde rolünü hatırlatsın:

```bash
sudo tee /etc/motd << 'EOF'

=========================================
  <HOSTNAME>  —  <ROL>
  Provider : <PROVIDER>
  Public IP: <IP>
  WG IP    : <WG_IP>
=========================================

EOF
```

Örnekler:

| Node | Rol satırı |
|------|-----------|
| gateway1 | Edge Proxy #1 — nginx, Cloudflare termination |
| node5 | Core #1 Primary — FastAPI, PostgreSQL, Redis, PgBouncer |
| node6 | Core #2 Standby — Keepalived, PG replica |
| node7 | Storage #1 — MinIO, nginx media/uploads |
| node8 | Storage #2 — MinIO, nginx media/uploads |
| node9 | Backup + Monitor + ClickHouse |
| node1 | Stream #1 — LiveKit |
| node4 | Stream #2 — LiveKit |
| node2 | AI Proxy — Groq/Gemini relay |
| node3 | Staging — FastAPI, PostgreSQL |
| gateway2 | Edge Proxy #2 — nginx, Cloudflare termination |

---

Bu 5 adım tamamlandıktan sonra `02_plan.md`'deki ilgili Faz'a geçilir. WireGuard kurulumu Faz 2'de, servis kurulumları ise node rolüne göre Faz 3–11 arasında yer alır.
