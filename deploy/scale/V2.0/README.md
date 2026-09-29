# teqlif V2.0 — Node Bootstrap

Her node için tek adımlı OS kurulum scripti. Script tamamlandığında:
- OS temeli (paketler, kullanıcı, SSH, dizinler, NTP, THP, auditd, logrotate)
- WireGuard anahtar çifti oluşturulmuş (pubkey ekranda)
- Node'a özgü servisler kurulu + enable edilmiş
- Config şablonları `/etc/teqlif/`, `/etc/wireguard/` vb. konumlara kopyalanmış
- Servisler başlatılmamış — önce placeholder'ları doldurman gerekiyor

## Ön Koşullar

```bash
# VPS'e root olarak SSH ile giriş yap, ardından:

# Seçenek A — Repo zaten klonlu ise:
bash /var/www/teqlif.com/deploy/scale/V2.0/scripts/bootstrap_<node>.sh

# Seçenek B — GitHub token ile ilk kurulum:
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
export SSH_PUBKEY="ssh-ed25519 AAAA... tucibeyin"
bash bootstrap_<node>.sh

# Seçenek C — Deploy key ile ilk kurulum:
export DEPLOY_KEY_PATH="/root/.ssh/deploy_key"
export SSH_PUBKEY="ssh-ed25519 AAAA... tucibeyin"
bash bootstrap_<node>.sh
```

## Node Haritası

| Script | Node | WG IP | Rol |
|--------|------|--------|-----|
| `bootstrap_gateway1.sh` | gateway1 | 10.10.0.2 | Edge Proxy #1 (Netcup NUE) |
| `bootstrap_gateway2.sh` | gateway2 | 10.10.0.9 | Edge Proxy #2 (Deluxhost AMS) |
| `bootstrap_node1.sh` | node1 | 10.10.0.1 | LiveKit Stream #1 |
| `bootstrap_node2.sh` | node2 | 10.10.0.3 | AI Proxy Primary |
| `bootstrap_node3.sh` | node3 | 10.10.0.4 | Staging Tam İzole |
| `bootstrap_node4.sh` | node4 | 10.10.0.6 | LiveKit Stream #2 |
| `bootstrap_node5.sh` | node5 | 10.10.0.5 | Core Primary (PG + Redis + App) |
| `bootstrap_node6.sh` | node6 | 10.10.0.7 | Core Standby |
| `bootstrap_node7.sh` | node7 | 10.10.0.8 | Storage Primary (MinIO) |
| `bootstrap_node8.sh` | node8 | 10.10.0.12 | Storage Secondary (MinIO) |
| `bootstrap_node9.sh` | node9 | 10.10.0.13 | Monitor + Backup + ClickHouse |

## Bootstrap Sonrası Zorunlu Adımlar (Her Node)

1. **WireGuard peer'larını doldur** — `/etc/wireguard/wg0.conf` içindeki `<PublicKey>` placeholder'larını her node'un gerçek public key'i ile değiştir
2. **WireGuard'ı başlat** — `wg-quick up wg0 && systemctl enable wg-quick@wg0`
3. **Mesh bağlantısını doğrula** — `ping 10.10.0.5` (core node)
4. **`.env` dosyasını doldur** — `~/teqlif-secrets.env`'den ilgili değerleri kopyala
5. **Guardian'ı başlat** — `systemctl start teqlif-guardian`

## Node'a Özgü Ek Adımlar

### node3 (Staging)
```bash
# Redis şifresi (redis-staging.conf)
sed -i "s/<staging_redis_pass>/${STAGING_REDIS_PASS}/" /etc/redis/redis-staging.conf
systemctl start redis-staging minio-staging

# Firebase + APNS gizli dosyalar (güvenli kanaldan kopyala)
# firebase-service-account.json → /etc/teqlif/
# AuthKey_*.p8               → /etc/teqlif/

# DB şeması
cd /var/www/teqlif.com/backend && \
  .venv/bin/python -m alembic upgrade head

# Tüm staging stack başlat
systemctl start livekit-staging teqlif-staging \
  teqlif-worker-staging teqlif-worker-critical-staging teqlif-ai-proxy
```

### node5 + node6 (Core HA)
```bash
# Sıra önemli! Önce node5, sonra node6:
# 1. node5'te: plan §4.3 PG replication + slot kurulumu
# 2. node6'da: pg_basebackup -h 10.10.0.5 -U replicator ...
# 3. Her ikisinde: systemctl start keepalived
# Bkz: deploy/scale/V2.0/documents/02_plan.md §4
```

### node7 + node8 (Storage HA)
```bash
# Her ikisinde MinIO başlat, sonra Site Replication kur:
# mc admin replicate add minio7 minio8
# Bkz: 02_plan.md §6.5
```

### node9 (Monitor)
```bash
# /data mount'unu doğrula (3.5TB HDD RAID)
df -h /data
# rclone B2 yapılandır
rclone config
# Tüm monitoring başlat
systemctl start prometheus loki alertmanager grafana-server
systemctl start teqlif-pg-receivewal
```

## Ortam Değişkenleri

| Değişken | Açıklama | Zorunlu |
|----------|----------|---------|
| `SSH_PUBKEY` | `tucibeyin` kullanıcısına eklenecek public key | Evet |
| `GITHUB_TOKEN` | Özel repo klonlama için GitHub PAT | Hayır* |
| `DEPLOY_KEY_PATH` | SSH deploy key dosya yolu | Hayır* |
| `REPO_DIR` | Repo klonlama hedefi (varsayılan: `/var/www/teqlif.com`) | Hayır |
| `LIVEKIT_VER` | LiveKit sürümü (varsayılan: `v1.7.2`) | Hayır |
| `MINIO_RELEASE` | MinIO sürümü (varsayılan: `RELEASE.2024-11-07T00-52-20Z`) | Hayır |

*Repo önceden klonluysa gerekmiyor.

## Cleanup

Her script tamamlandığında (başarılı veya hatalı) otomatik olarak:
- `apt-get clean` + `apt-get autoremove`
- `/tmp/teqlif-bootstrap-*` geçici dosyaları silme

çalışır. Bu `trap EXIT` ile garanti edilir.
