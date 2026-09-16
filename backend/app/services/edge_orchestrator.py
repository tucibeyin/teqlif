from enum import Enum
import json
import logging
from typing import Optional, Dict, Any

from app.utils.redis_client import get_redis
from app.config import settings

logger = logging.getLogger(__name__)

class ServiceType(Enum):
    MEDIA = "media"      # Yüksek CPU, düşük latency (VoIP, Canlı Yayın)
    STORAGE = "storage"  # Yüksek Disk kapasitesi (MinIO Yükleme)
    # İleride eklenebilecek: AI_MODEL, BATCH_PROCESS vb.


class EdgeOrchestrator:
    """
    Teqlif V1.4 - Generic Edge Allocator (Strateji Deseni)
    Hangi Edge sunucusunun hangi işlem için en uygun olduğunu belirler.
    Tamamen servis tiplerine (ServiceType) göre soyutlanmıştır.
    
    Bu sınıf (Resource Decision Engine); medya, ses veya dosya fark etmeksizin
    sadece donanım metriklerine bakarak kaynak tahsisi yapar.
    """

    async def get_edge_metrics(self) -> list[dict]:
        """Tüm Edge sunucularının metriklerini Redis'ten okur (Service Discovery)."""
        redis = await get_redis()
        keys = await redis.keys("edge:metrics:*")
        
        metrics_list = []
        if not keys:
            return metrics_list
            
        raw_values = await redis.mget(*keys)
        for val in raw_values:
            if val:
                try:
                    metrics_list.append(json.loads(val))
                except Exception as e:
                    logger.error(f"[Orchestrator] JSON parse hatası: {e}")
        return metrics_list

    async def allocate_node(self, service_type: ServiceType) -> Optional[Dict[str, Any]]:
        """
        Gelen servis tipine göre (Strateji Deseni) en iyi Edge node'unu seçer.
        """
        metrics = await self.get_edge_metrics()
        
        if not metrics:
            logger.warning(f"[Orchestrator] Hiçbir Edge metriği bulunamadı! {service_type.value} için Fallback uygulanıyor.")
            return self._get_fallback_node()
            
        best_node = None
        
        if service_type == ServiceType.MEDIA:
            # MEDIA Stratejisi: En düşük CPU kullanımı olan Node seçilir
            best_node = min(metrics, key=lambda x: x.get('cpu_percent', 100.0))
            
        elif service_type == ServiceType.STORAGE:
            # STORAGE Stratejisi: Disk kotası en az dolu olan Node seçilir
            best_node = min(metrics, key=lambda x: x.get('disk_percent', 100.0))
            
            # Quota kontrolü
            if best_node.get('disk_percent', 0) > settings.minio_storage_quota_percent:
                logger.warning(f"[Orchestrator] Seçilen Storage Node ({best_node.get('node_id')}) belirlenen kotayı ({settings.minio_storage_quota_percent}%) aşıyor!")

        if best_node:
            logger.info(f"[Orchestrator] {service_type.value.upper()} servisi için Node seçildi: {best_node.get('node_id')}")
            return best_node
            
        return self._get_fallback_node()

    def _get_fallback_node(self) -> Dict[str, Any]:
        """Eğer Ajanlar çökmüşse veya Redis'te metrik yoksa Config'deki ilk statik adresleri döner."""
        livekit_url = settings.edge_livekit_urls[0] if settings.edge_livekit_urls else ""
        minio_url = settings.edge_minio_urls[0] if settings.edge_minio_urls else ""
        return {
            "node_id": "fallback_node",
            "livekit_url": livekit_url,
            "minio_url": minio_url
        }

# Uygulama genelinde kullanılacak Singleton instance
orchestrator = EdgeOrchestrator()
