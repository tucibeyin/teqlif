"""
node2 AI proxy istemcisi — node1'den çağrılır.

Sıra:
  1. node2 çalışıyorsa /generate endpoint'ine ilet (45s timeout)
  2. node2 down veya hata → lokal fallback (Groq-only, EU IP'den Gemini yoktur)
"""
import asyncio

import httpx

from app.config import settings
from app.core.logger import get_logger
from app.services.ml.llm_service import generate_listing_description

logger = get_logger(__name__)


async def generate_via_node2(params: dict) -> tuple[str, str]:
    """
    (description, provider) döndürür.
    node2 erişilemez veya hata verirse lokal registry'ye düşer.
    """
    if settings.node2_ai_proxy_url:
        try:
            async with httpx.AsyncClient(timeout=45.0) as client:
                resp = await client.post(
                    f"{settings.node2_ai_proxy_url}/generate",
                    json=params,
                    headers={"X-Internal-Token": settings.node2_internal_token},
                )
            resp.raise_for_status()
            data = resp.json()
            return data["text"], data["provider"]
        except Exception as exc:
            logger.warning("[AI-PROXY] node2 başarısız, lokal fallback: %s", exc)

    # Lokal fallback — EU IP'de Gemini yoktur; registry sadece Groq içerir
    return await generate_listing_description(**params)
