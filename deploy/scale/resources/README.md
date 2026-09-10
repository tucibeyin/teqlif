# deploy/scale/resources — Tek Kaynak Nokta

Bu dizin tüm node ve ortam kombinasyonları için `.env` şablonlarını ve
`requirements` dosyalarını içerir. Path'ler bir kez tanımlanır, versiyondan
bağımsız olarak **hiç değişmez**.

---

## Dosya isimlendirme

| Tür          | Şablon                          | Örnek                              |
|--------------|---------------------------------|------------------------------------|
| requirements | `{node}_{ortam}_requirements.txt` | `node1_production_requirements.txt` |
| .env         | `.env.{node}.{ortam}`           | `.env.node1.production`            |

---

## Mevcut kombinasyonlar

| Node    | Ortam      | requirements                        | .env                        |
|---------|------------|-------------------------------------|-----------------------------|
| node1   | production | `node1_production_requirements.txt` | `.env.node1.production`     |
| node1   | staging    | `node1_staging_requirements.txt`    | `.env.node1.staging`        |
| node2   | production | `node2_production_requirements.txt` | `.env.node2.production`     |
| node2   | cfFailover | —                                   | `.env.node2.cfFailover`     |

---

## Standart venv konumu — tüm node'lar

```
/var/www/teqlif.com/venv/
```

Oluşturma (her node'da bir kez):

```bash
sudo apt install python3.13-venv -y
cd /var/www/teqlif.com
python3 -m venv venv
```

Pip install:

```bash
# node1 production
venv/bin/pip install -r deploy/scale/resources/node1_production_requirements.txt

# node1 staging
venv/bin/pip install -r deploy/scale/resources/node1_staging_requirements.txt

# node2 production
venv/bin/pip install -r deploy/scale/resources/node2_production_requirements.txt
```

---

## Systemd EnvironmentFile path'leri (bir kez tanımlandı)

| Servis                   | EnvironmentFile                                          |
|--------------------------|----------------------------------------------------------|
| teqlif.service           | `.../deploy/scale/resources/.env.node1.production`       |
| teqlif-staging.service   | `.../deploy/scale/resources/.env.node1.staging`          |
| teqlif-worker.service    | `.../deploy/scale/resources/.env.node1.production`       |
| teqlif-ai-proxy.service  | `.../deploy/scale/resources/.env.node2.production`       |
| cf-failover.service      | `.../deploy/scale/resources/.env.node2.cfFailover`       |

---

## Yeni versiyon / yeni alan eklenince

1. İlgili `.env.*` dosyasına yeni satır ekle
2. Gerekirse `requirements` dosyasını güncelle
3. Commit + push → node'larda `git pull` yeterli, **path değişikliği yok**
