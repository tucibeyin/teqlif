import os
import json
import time
import logging
import psutil
import redis

# Logging yapılandırması
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("EdgeMetricsAgent")

def get_env_or_die(key: str) -> str:
    val = os.getenv(key)
    if not val:
        logger.error(f"Missing required environment variable: {key}")
        exit(1)
    return val

def main():
    logger.info("Starting Edge Metrics Agent...")
    
    core_redis_url = get_env_or_die("CORE_REDIS_URL")
    node_id = get_env_or_die("EDGE_NODE_ID")
    interval = int(os.getenv("EDGE_METRICS_INTERVAL_SEC", "3"))
    
    # Standalone MinIO mount noktası (varsayılan: /)
    minio_path = os.getenv("MINIO_VOLUMES", "/")
    if minio_path.startswith('"') and minio_path.endswith('"'):
        minio_path = minio_path[1:-1]
    
    logger.info(f"Node ID: {node_id}")
    logger.info(f"Core Redis: {core_redis_url}")
    logger.info(f"Interval: {interval}s")
    
    # Redis bağlantısı
    r = redis.Redis.from_url(core_redis_url, decode_responses=True)
    
    try:
        r.ping()
        logger.info("Successfully connected to Core Redis.")
    except Exception as e:
        logger.error(f"Failed to connect to Redis: {e}")
        exit(1)

    redis_key = f"edge:metrics:{node_id}"
    
    # Optional URLs if we want to announce ourselves
    livekit_url = os.getenv("EDGE_LIVEKIT_URL", "")
    minio_url = os.getenv("EDGE_MINIO_URL", "")

    while True:
        try:
            # CPU (1 saniyelik bloklama ile ortalama alır)
            cpu = psutil.cpu_percent(interval=1)
            
            # RAM
            mem = psutil.virtual_memory()
            ram_percent = mem.percent
            
            # Disk (Quota & Storage için kritik)
            try:
                disk = psutil.disk_usage(minio_path)
                disk_percent = disk.percent
            except Exception:
                disk_percent = 0.0

            # Ağ trafiği (Mevcut I/O durumu - opsiyonel delta hesaplanabilir)
            net_io = psutil.net_io_counters()

            metrics = {
                "node_id": node_id,
                "timestamp": int(time.time()),
                "cpu_percent": cpu,
                "ram_percent": ram_percent,
                "disk_percent": disk_percent,
                "net_bytes_sent": net_io.bytes_sent,
                "net_bytes_recv": net_io.bytes_recv,
                "livekit_url": livekit_url,
                "minio_url": minio_url
            }

            # TTL = interval * 2 (Eğer ajan ölürse 6 saniye sonra orkestratör bu node'u listeden düşürür)
            ttl = interval * 2
            r.set(redis_key, json.dumps(metrics), ex=ttl)
            
            logger.debug(f"Pushed metrics to {redis_key}: CPU={cpu}% DISK={disk_percent}%")
            
            # 1 saniyesi psutil.cpu_percent() içinde geçtiği için (interval-1) kadar bekliyoruz.
            sleep_time = max(0, interval - 1)
            time.sleep(sleep_time)

        except Exception as e:
            logger.error(f"Error in metrics loop: {e}")
            time.sleep(interval)

if __name__ == "__main__":
    main()
