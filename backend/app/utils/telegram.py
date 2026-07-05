import httpx
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

async def send_telegram_message(text: str) -> bool:
    """
    Sends a message to the configured Telegram chat using the bot token.
    Returns True if successful, False otherwise.
    """
    if not settings.telegram_bot_token or not settings.telegram_chat_id:
        logger.warning("[Telegram] Telegram_bot_token veya telegram_chat_id tanımlı değil. Mesaj gönderilmedi.")
        return False

    url = f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage"
    payload = {
        "chat_id": settings.telegram_chat_id,
        "text": text,
        "parse_mode": "HTML"
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload)
            response.raise_for_status()
            logger.info("[Telegram] Mesaj başarıyla gönderildi.")
            return True
    except httpx.HTTPError as exc:
        logger.error("[Telegram] Mesaj gönderilemedi: %s", exc)
        return False
    except Exception as exc:
        logger.error("[Telegram] Beklenmeyen bir hata oluştu: %s", exc)
        return False
