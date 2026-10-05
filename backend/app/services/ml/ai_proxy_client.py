"""
AI proxy istemcisi — node1'den çağrılır.

Failover zinciri (Redis keşfi):
  1. En düşük ai_proxy_priority değerine sahip sağlıklı AI node (şu an node5)
  2. Sonraki öncelikli sağlıklı node (varsa)
  3. Lokal llm_service.py  (son çare — node1'de API key yoksa 503 döner)

Keşif: Core Redis'teki edge:metrics:* anahtarları okunur.
  Her node services.ai_proxy.healthy=true ve ai_proxy_url set etmişse
  listeye alınır; ai_proxy_priority (küçük = önce) ile sıralanır.

Timeout stratejisi:
  - connect=5s  → kapalı node'u 5 saniyede tespit et, hemen fallback'e geç
  - read=45s    → proxy bağlandıysa LLM yanıtını 45 saniyeye kadar bekle
"""
import json
import time

import httpx
import redis.asyncio as aioredis

from app.config import settings
from app.core.logger import get_logger
from app.services.ml.llm_service import generate_listing_description

logger = get_logger(__name__)

_TIMEOUT = httpx.Timeout(connect=5.0, read=45.0, write=5.0, pool=5.0)

_DISCOVERY_CACHE: list[str] = []
_DISCOVERY_CACHE_AT: float = 0.0
_DISCOVERY_TTL = 30.0  # saniye — Redis'ten bu aralıkta taze liste alınır


async def _discover_ai_proxy_urls() -> list[str]:
    """Redis edge:metrics:* anahtarlarından sağlıklı AI proxy URL'lerini keşfeder."""
    global _DISCOVERY_CACHE, _DISCOVERY_CACHE_AT
    if time.monotonic() - _DISCOVERY_CACHE_AT < _DISCOVERY_TTL and _DISCOVERY_CACHE:
        return _DISCOVERY_CACHE
    try:
        r = aioredis.from_url(settings.redis_url, decode_responses=True)
        async with r:
            keys = await r.keys("edge:metrics:*")
            nodes: list[tuple[int, str]] = []  # (priority, url)
            for key in keys:
                raw = await r.get(key)
                if not raw:
                    continue
                try:
                    data = json.loads(raw)
                except Exception:
                    continue
                ai_url = data.get("ai_proxy_url")
                if not ai_url:
                    continue
                svc = data.get("services", {}).get("ai_proxy", {})
                if not svc.get("healthy"):
                    continue
                priority = int(data.get("ai_proxy_priority", 100))
                nodes.append((priority, ai_url))
        nodes.sort(key=lambda x: x[0])
        urls = [url for _, url in nodes]
        if urls:
            _DISCOVERY_CACHE = urls
            _DISCOVERY_CACHE_AT = time.monotonic()
        return urls
    except Exception as exc:
        logger.warning("[AI-PROXY] Redis keşfi başarısız: %s", exc)
        return _DISCOVERY_CACHE  # stale cache — Redis geçici olarak erişilemez


async def _call_proxy(url: str, params: dict) -> tuple[str, str] | None:
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.post(
                f"{url}/generate",
                json=params,
                headers={"X-Internal-Token": settings.ai_proxy_internal_token},
            )
        resp.raise_for_status()
        data = resp.json()
        return data["text"], data["provider"]
    except Exception as exc:
        logger.warning("[AI-PROXY] %s başarısız: %s", url, exc)
        return None


async def generate_via_proxy(params: dict) -> tuple[str, str]:
    """
    (description, provider) döndürür.
    Keşfedilen tüm AI proxy node'ları erişilemez veya hata verirse
    lokal llm_service'e düşer.
    """
    proxy_urls = await _discover_ai_proxy_urls()
    for proxy_url in proxy_urls:
        result = await _call_proxy(proxy_url, params)
        if result is not None:
            return result

    logger.error("[AI-PROXY] Tüm proxy node'ları erişilemez, lokal fallback deneniyor")
    return await generate_listing_description(**params)
