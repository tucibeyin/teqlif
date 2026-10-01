# Teqlif Scale V2.1 — Sunucu Hazırlık Rehberi

Bu dizin, V2.1 (6-node, gateway'siz, tam WireGuard mesh) mimarisine ait tüm sunucu yapılandırmalarının tek doğruluk kaynağıdır. Bootstrap scriptleri çalıştırılmadan önce her node'da aşağıdaki adımlar **manuel olarak** tamamlanmalıdır.

---

## Node Haritası

| Node | Rol | Provider | Public IP | WG IP |
|------|-----|----------|-----------|-------|
| node1 | Core API + DB + Redis + MinIO | OVH Gravelines FR | 193.70.46.74 | 10.10.0.1 |
| node2 | Backup + Monitoring + ClickHouse | OVH Saarbrücken DE | 135.125.223.43 | 10.10.0.2 |
| node3 | LiveKit Streaming #1 | OVH Frankfurt DE | 51.75.74.124 | 10.10.0.3 |
| node4 | LiveKit Streaming #2 | OVH Frankfurt DE | 135.125.175.223 | 10.10.0.4 |
| node5 | Staging + AI Secondary | ZAP Münster DE | 45.146.252.165 | 10.10.0.5 |
| node6 | AI Primary | ZAP Virginia US | 5.249.165.10 | 10.10.0.6 |

---

## Adım 1 — Hostname

```bash
sudo hostnamectl set-hostname node1   # node numarasını değiştir
echo "127.0.1.1 node1" | sudo tee -a /etc/hosts
```

---

## Adım 2 — Temel Paketler + Repo Dizini

```bash
sudo apt update && sudo apt install -y git btop curl wget

sudo mkdir -p /var/www/teqlif.com
sudo chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

---

## Adım 3 — GitHub Deploy Key

Her node için ayrı deploy key oluşturulur. Aynı repo'ya birden fazla deploy key eklenebilir.

```bash
su - tucibeyin

ssh-keygen -t ed25519 -C "tucibeyin@gmail.com" -f ~/.ssh/github_key -N ""

cat >> ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_key
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config

cat ~/.ssh/github_key.pub
```

> **GitHub:** Repo → Settings → Deploy Keys → Add deploy key → **Allow write access** işaretle.

```bash
git clone git@github.com:tucibeyin/teqlif.git /var/www/teqlif.com

git config --global user.name "tucibeyin"
git config --global user.email "tucibeyin@gmail.com"
```

---

## Adım 4 — MOTD

```bash
sudo tee /etc/motd << 'EOF'

=========================================
  <HOSTNAME>  —  <ROL>
  Provider : <PROVIDER>
  Public IP: <PUBLIC_IP>
  WG IP    : <WG_IP>
=========================================

EOF
```

Her node için değerler:

| Node | HOSTNAME | ROL | PROVIDER | PUBLIC_IP | WG_IP |
|------|----------|-----|----------|-----------|-------|
| node1 | node1 | Core API + DB + Redis + MinIO | OVH Gravelines FR | 193.70.46.74 | 10.10.0.1 |
| node2 | node2 | Backup + Monitoring + ClickHouse | OVH Saarbrücken DE | 135.125.223.43 | 10.10.0.2 |
| node3 | node3 | LiveKit Streaming #1 | OVH Frankfurt DE | 51.75.74.124 | 10.10.0.3 |
| node4 | node4 | LiveKit Streaming #2 | OVH Frankfurt DE | 135.125.175.223 | 10.10.0.4 |
| node5 | node5 | Staging + AI Secondary | ZAP Münster DE | 45.146.252.165 | 10.10.0.5 |
| node6 | node6 | AI Primary | ZAP Virginia US | 5.249.165.10 | 10.10.0.6 |

---

## Adım 5 — Bootstrap

Bu 4 adım tamamlandıktan sonra bootstrap çalıştırılır. `secrets.env` varsa scp ile aktarılır, bootstrap bitince otomatik silinir (shred).

```bash
# Lokal'den node'a secrets.env gönder:
scp secrets.env tucibeyin@<NODE_IP>:/tmp/teqlif-secrets.env

# Node'da (root olarak):
SECRETS_FILE=/tmp/teqlif-secrets.env \
  sudo bash /var/www/teqlif.com/deploy/scale/V2.1/scripts/bootstrap_<NODE>.sh
```

Secrets olmadan (sonradan elle doldurmak için):
```bash
sudo bash /var/www/teqlif.com/deploy/scale/V2.1/scripts/bootstrap_<NODE>.sh
```

### Bootstrap sırası

Node'lar bağımsız bootstrap edilir; sıra önerilir ama zorunlu değildir. WireGuard mesh `wg_mesh_apply.sh` ile tüm node'lar hazır olduktan sonra kurulur.

```
node1 (Core)  →  node2 (Backup)  →  node5 (Staging)  →  node6 (AI)
                                 →  node3 (LiveKit)   →  node4 (LiveKit)
```

### WireGuard mesh (tüm bootstrap'lar bittikten sonra)

Her node'dan `cat /etc/wireguard/pubkey` alınır, `secrets.env` Bölüm 3'e girilir:

```bash
# Lokal'den:
bash /var/www/teqlif.com/deploy/scale/V2.1/scripts/wg_mesh_apply.sh
```
