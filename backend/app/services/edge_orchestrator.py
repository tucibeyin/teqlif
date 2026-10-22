"""
Edge Orchestrator V2.1 — cluster-aware routing engine.

Redis'teki canlı node metriklerini okur, servis tipine göre en uygun
node'u composite scoring ile seçer. Agent TTL ile ölmüşse Redis'ten
otomatik düşer, buraya yansır.
"""

import json
import logging
from enum import Enum
from typing import Any, Dict, List, Optional

from app.config import settings
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

_MAX_MEDIA_PARTICIPANTS = 500  # medya score normalizasyon kapasitesi
_NODE_HEALTHY_STALE_SEC = 15   # edge:metrics TTL eşiği — agent 5s'de bir yazar


class ServiceType(Enum):
    MEDIA   = "media"
    STORAGE = "storage"
    AI      = "ai"


class EdgeOrchestrator:

    async def get_all_metrics(self) -> List[Dict[str, Any]]:
        """Tüm aktif node'ların canlı metriklerini döner (TTL ile ölü ajanlar otomatik çıkar)."""
        redis = await get_redis()
        keys  = await redis.keys("edge:metrics:*")
        if not keys:
            return []
        raw = await redis.mget(*keys)
        result = []
        for val in raw:
            if val:
                try:
                    result.append(json.loads(val))
                except Exception as e:
                    logger.error(f"JSON parse error: {e}")
        return result

    async def all_media_nodes(self) -> List[Dict[str, Any]]:
        """Tüm sağlıklı media node'larını döner; metrik yoksa settings.edge_livekit_urls fallback."""
        all_m = await self.get_all_metrics()
        nodes = [
            m for m in all_m
            if "media" in m.get("node_type", [])
            and m.get("services", {}).get("livekit", {}).get("healthy", False)
            and m.get("livekit_url")
        ]
        if not nodes:
            from app.config import settings as _s
            return [{"livekit_url": url, "node_id": f"fallback-{i}"}
                    for i, url in enumerate(_s.edge_livekit_urls) if url]
        return nodes

    async def is_node_healthy(self, node_id: str) -> bool:
        """edge:metrics:{node_id} anahtarı mevcutsa node sağlıklıdır.

        Agent 5s'de bir yazar; TTL aşılmışsa anahtar yoktur → unhealthy.
        """
        if not node_id or node_id.startswith("fallback"):
            return False
        redis = await get_redis()
        return await redis.exists(f"edge:metrics:{node_id}") == 1

    async def allocate_node(
        self,
        service_type: ServiceType,
        exclude_node_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Servis tipine göre en uygun node'u seçer; metrik yoksa config fallback.

        exclude_node_id: Kural 3 failover'da çöken node'u seçim dışı bırakır.
        """
        all_m = await self.get_all_metrics()
        if not all_m:
            logger.debug("Metrik yok — %s için config fallback", service_type.value)
            return self._fallback(service_type)

        if service_type == ServiceType.MEDIA:
            return self._pick_media(all_m, exclude_node_id=exclude_node_id)
        if service_type == ServiceType.STORAGE:
            return self._pick_storage(all_m)
        if service_type == ServiceType.AI:
            return self._pick_ai(all_m)
        return self._fallback(service_type)

    async def resolve_stream_endpoint(self, stream) -> Dict[str, Any]:
        """Relay aktifse relay node'una, değilse source node'una yönlendirir.

        Returns: {"livekit_url": str, "room_name": str, "node_id": str}
        """
        redis = await get_redis()
        relay_data = await redis.get(f"live:relay:ready:{stream.room_name}")
        if relay_data:
            try:
                info = json.loads(relay_data)
                return {
                    "livekit_url": info["relay_url"],
                    "room_name":   info["relay_room"],
                    "node_id":     info.get("relay_node_id", "relay"),
                }
            except Exception:
                pass  # bozuk relay verisi — source'a düş
        return {
            "livekit_url": stream.livekit_url or "",
            "room_name":   stream.room_name,
            "node_id":     getattr(stream, "source_node_id", None) or "unknown",
        }

    # ── Node seçiciler ────────────────────────────────────────────────────

    def _pick_media(self, metrics: List[Dict], exclude_node_id: Optional[str] = None) -> Dict:
        candidates = [
            m for m in metrics
            if "media" in m.get("node_type", [])
            and m.get("services", {}).get("livekit", {}).get("healthy", False)
            and m.get("livekit_url")
            and m.get("node_id") != exclude_node_id
        ]
        if not candidates:
            logger.warning("Sağlıklı media node yok — fallback")
            return self._fallback(ServiceType.MEDIA)

        def score(m: Dict) -> float:
            p     = m.get("services", {}).get("livekit", {}).get("participants", 0)
            p_pct = min(p / _MAX_MEDIA_PARTICIPANTS * 100, 100)
            return m.get("cpu_percent", 50.0) * 0.3 + p_pct * 0.7

        best = min(candidates, key=score)
        logger.info(
            f"Media node seçildi: {best['node_id']} "
            f"(score={score(best):.1f}, "
            f"cpu={best.get('cpu_percent')}%, "
            f"participants={best.get('services', {}).get('livekit', {}).get('participants', 0)})"
        )
        return best

    def _pick_storage(self, metrics: List[Dict]) -> Dict:
        candidates = [
            m for m in metrics
            if "storage" in m.get("node_type", [])
            and m.get("services", {}).get("minio", {}).get("healthy", False)
            and m.get("minio_url")
        ]
        if not candidates:
            return self._fallback(ServiceType.STORAGE)

        best = min(candidates, key=lambda m: m.get("disk_percent", 100.0))
        if best.get("disk_percent", 0) > settings.minio_storage_quota_percent:
            logger.warning(
                f"Storage {best['node_id']} disk={best.get('disk_percent')}% "
                f"(kota={settings.minio_storage_quota_percent}%)"
            )
        logger.info(f"Storage node seçildi: {best['node_id']} ({best.get('disk_percent')}% disk)")
        return best

    def _pick_ai(self, metrics: List[Dict]) -> Dict:
        candidates = [
            m for m in metrics
            if "ai" in m.get("node_type", [])
            and m.get("services", {}).get("ai_proxy", {}).get("healthy", False)
            and m.get("ai_proxy_url")
        ]
        if not candidates:
            return self._fallback(ServiceType.AI)

        # CPU + RAM toplamı en düşük node
        best = min(
            candidates,
            key=lambda m: m.get("cpu_percent", 50.0) + m.get("ram_percent", 50.0),
        )
        logger.info(
            f"AI node seçildi: {best['node_id']} "
            f"(cpu={best.get('cpu_percent')}%, ram={best.get('ram_percent')}%)"
        )
        return best

    # ── Fallback ──────────────────────────────────────────────────────────

    def _fallback(self, service_type: ServiceType) -> Dict[str, Any]:
        node: Dict[str, Any] = {
            "node_id":     "fallback",
            "livekit_url":  "",
            "minio_url":    "",
            "ai_proxy_url": "",
        }
        if service_type == ServiceType.MEDIA:
            url = settings.edge_livekit_urls[0] if settings.edge_livekit_urls else ""
            node["livekit_url"] = url
            # H1: URL → node_id çözümü; harita yoksa "fallback" kalır
            node["node_id"] = settings.edge_livekit_node_map.get(url, "fallback")
        elif service_type == ServiceType.STORAGE:
            node["minio_url"] = settings.edge_minio_urls[0] if settings.edge_minio_urls else ""
        elif service_type == ServiceType.AI:
            node["ai_proxy_url"] = settings.ai_proxy_url
        return node


orchestrator = EdgeOrchestrator()
