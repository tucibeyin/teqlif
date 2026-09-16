#!/usr/bin/env bash
# deploy/scale/V1.4/node1/resources/node1_cleanup.sh
# DİKKAT: Bu script, Node1'i V1.3 Monolithic formundan tamamen arındırmak için 
# "Scorched Earth" (Yakıp Yıkma) mantığıyla çalışır.
# PostgreSQL, ClickHouse, eski FastAPI backend'i, Nginx ve eski verileri KALICI OLARAK SİLER.
# Node'u formatlamadan, V1.4 Edge 1 kurulumuna (Sıfır Durum) hazır hale getirir.

set -euo pipefail

echo "========================================================================="
echo " DİKKAT: NODE1 V1.3 TEMİZLİK SCRİPTİ BAŞLIYOR!"
echo " Bu işlem PostgreSQL, ClickHouse, Teqlif Backend ve tüm eski verileri silecektir."
echo " Geri dönüşü yoktur. Devam etmek için 5 saniye bekleyin (veya Ctrl+C ile iptal edin)..."
echo "========================================================================="
sleep 5

echo "==> 1. Eski servisler durduruluyor..."
SERVICES_TO_STOP=(teqlif teqlif-worker teqlif-worker-critical postgresql clickhouse-server nginx redis-server teqlif-backup.timer teqlif-backup redis-backup.timer redis-backup)
for svc in "${SERVICES_TO_STOP[@]}"; do
  sudo systemctl stop "$svc" 2>/dev/null || true
  sudo systemctl disable "$svc" 2>/dev/null || true
done

echo "==> 2. Eski systemd dosyaları siliniyor..."
sudo rm -f /etc/systemd/system/teqlif.service
sudo rm -f /etc/systemd/system/teqlif-worker.service
sudo rm -f /etc/systemd/system/teqlif-worker-critical.service
sudo rm -f /etc/systemd/system/teqlif-backup.*
sudo rm -f /etc/systemd/system/redis-backup.*
sudo systemctl daemon-reload

echo "==> 3. Monolithic bileşenler (Postgres, ClickHouse, Nginx) sistemden tamamen (purge) kaldırılıyor..."
sudo apt-get purge -y "postgresql*" "clickhouse*" "nginx*" "nginx-common" 2>/dev/null || true

echo "==> 4. Veritabanı ve konfigürasyon dizinleri (Data & Config) siliniyor..."
sudo rm -rf /var/lib/postgresql
sudo rm -rf /etc/postgresql
sudo rm -rf /var/log/postgresql

sudo rm -rf /var/lib/clickhouse
sudo rm -rf /etc/clickhouse-server
sudo rm -rf /etc/clickhouse-client
sudo rm -rf /var/log/clickhouse-server

sudo rm -rf /etc/nginx
sudo rm -rf /var/log/nginx

echo "==> 5. Redis ve eski MinIO verileri sıfırlanıyor (Temiz Edge durumu için)..."
sudo rm -rf /var/lib/redis/* 2>/dev/null || true
sudo rm -rf /var/lib/minio/* 2>/dev/null || true

echo "==> 6. Teqlif eski ortamı (Python venv, loglar) temizleniyor..."
REPO_ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
echo "Repo Root: $REPO_ROOT"
if [[ -d "$REPO_ROOT/venv" ]]; then
  sudo rm -rf "$REPO_ROOT/venv"
fi
sudo rm -rf /var/log/teqlif/* 2>/dev/null || true
sudo rm -rf /var/backups/teqlif/* 2>/dev/null || true

echo "==> 7. İşletim sistemi artıkları temizleniyor..."
sudo apt-get autoremove -y --purge
sudo apt-get clean

echo "========================================================================="
echo " TEMİZLİK TAMAMLANDI!"
echo " Node1 artık eski V1.3 yüklerinden (DB, Backend, Nginx) tamamen arındırıldı."
echo " Şimdi 'bootstrap_node1.sh' scriptini çalıştırarak temiz bir Edge 1 kurabilirsiniz."
echo "========================================================================="
