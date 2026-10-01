"""
AI proxy istemcisi — node1'den çağrılır.

Failover zinciri:
  1. node6 :8001  (Primary — Virginia US, Gemini kısıtsız + Groq)
  2. node5 :8001  (Secondary — EU, Groq + Gemini limitli)
  3. Lokal llm_service.py  (son çare — node1'de API key yoksa 503 döner)

Timeout stratejisi:
  - connect=5s  → kapalı node'u 5 saniyede tespit et, hemen fallback'e geç
  - read=45s    → proxy bağlandıysa LLM yanıtını 45 saniyeye kadar bekle
"""
import httpx

from app.config import settings
from app.core.logger import get_logger
from app.services.ml.llm_service import generate_listing_description

logger = get_logger(__name__)

_TIMEOUT = httpx.Timeout(connect=5.0, read=45.0, write=5.0, pool=5.0)


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
    node6 ve node5 erişilemez veya hata verirse lokal llm_service'e düşer.
    """
    for proxy_url in (settings.ai_proxy_url, settings.ai_proxy_fallback_url):
        if not proxy_url:
            continue
        result = await _call_proxy(proxy_url, params)
        if result is not None:
            return result

    # Lokal fallback — node1'de API key tanımlıysa çalışır, yoksa AIServiceBusyException
    logger.error("[AI-PROXY] node6 ve node5 erişilemez, lokal fallback deneniyor")
    return await generate_listing_description(**params)
