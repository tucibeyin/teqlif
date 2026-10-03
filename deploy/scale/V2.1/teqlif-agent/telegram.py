"""teqlif-agent — Telegram bildirimi."""
from __future__ import annotations

import logging

import aiohttp

logger = logging.getLogger("teqlif-agent.telegram")


async def send(bot_token: str, chat_id: str, text: str) -> None:
    if not bot_token or not chat_id:
        logger.debug("Telegram config eksik, bildirim atlandı.")
        return
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
    try:
        async with aiohttp.ClientSession() as s:
            async with s.post(url, json=payload, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    logger.warning("Telegram hata %d: %s", resp.status, body[:200])
    except Exception as exc:
        logger.warning("Telegram gönderilemedi: %s", exc)
