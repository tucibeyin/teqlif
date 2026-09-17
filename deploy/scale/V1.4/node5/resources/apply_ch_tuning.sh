#!/usr/bin/env bash
# deploy/scale/V1.4/node5/resources/apply_ch_tuning.sh
# node5 ClickHouse performans tuning ("Deli Gömleği" / Straitjacket)
# ZAP-Hosting Donanımı: 4 Core EPYC, 7.8 GB RAM (NVMe)
# 
# ClickHouse'un sistem RAM'ini tüketip (OOM) PostgreSQL veya Orchestrator'ı çökertmesini
# engellemek için kesin RAM kullanım sınırı (2.0 GB) uygulanır.
set -euo pipefail

echo "==> ClickHouse RAM Kısıtlaması (Deli Gömleği) Uygulanıyor..."

# ClickHouse user configuration override dizini
sudo mkdir -p /etc/clickhouse-server/users.d

# Maksimum RAM'i 2GB (2147483648 bytes) olarak sınırla
sudo tee /etc/clickhouse-server/users.d/memory_limits.xml > /dev/null << 'EOF'
<clickhouse>
    <profiles>
        <default>
            <max_memory_usage>2147483648</max_memory_usage>
            <max_memory_usage_for_user>2147483648</max_memory_usage_for_user>
            <max_bytes_before_external_group_by>1073741824</max_bytes_before_external_group_by>
            <max_bytes_before_external_sort>1073741824</max_bytes_before_external_sort>
        </default>
    </profiles>
</clickhouse>
EOF

# Global server yapılandırması
sudo mkdir -p /etc/clickhouse-server/config.d
sudo tee /etc/clickhouse-server/config.d/max_server_memory.xml > /dev/null << 'EOF'
<clickhouse>
    <max_server_memory_usage>2147483648</max_server_memory_usage>
</clickhouse>
EOF

echo "==> ClickHouse yeniden başlatılıyor..."
sudo systemctl restart clickhouse-server

echo "Tuning tamamlandı. ClickHouse artık maksimum 2.0GB RAM kullanabilir."
