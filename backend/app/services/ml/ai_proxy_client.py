"""
AI proxy istemcisi — node1'den çağrılır.

Fallback zinciri:
  1. node2 :8080  (primary — ~100ms WG gecikme)
  2. node3 :8080  (secondary — ~80ms WG gecikme)
  3. node1 local  (son çare — Groq-only, EU IP'den Gemini yoktur)
"""
import httpx

from app.config import settings
from app.core.logger import get_logger
from app.services.ml.llm_service import generate_listing_description

logger = get_logger(__name__)

_TIMEOUT = 30.0


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
    node2 ve node3 erişilemez veya hata verirse lokal registry'ye düşer.
    """
    for proxy_url in (settings.node2_ai_proxy_url, settings.node3_ai_proxy_url):
        if not proxy_url:
            continue
        result = await _call_proxy(proxy_url, params)
        if result is not None:
            return result

    # Lokal fallback — EU IP'de Gemini yoktur; registry sadece Groq içerir
    return await generate_listing_description(**params)
