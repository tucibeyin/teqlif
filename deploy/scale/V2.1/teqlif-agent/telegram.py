"""teqlif-agent — Telegram bildirimi + interaktif API."""
from __future__ import annotations

import json
import logging

import aiohttp

logger = logging.getLogger("teqlif-agent.telegram")

_TIMEOUT = aiohttp.ClientTimeout(total=10)


async def send(
    bot_token: str,
    chat_id: str,
    text: str,
    reply_markup: dict | None = None,
) -> int | None:
    """Mesaj gönderir. reply_markup verilirse inline klavye ekler. message_id döner."""
    if not bot_token or not chat_id:
        logger.debug("Telegram config eksik, bildirim atlandı.")
        return None
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload: dict = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
    if reply_markup:
        payload["reply_markup"] = json.dumps(reply_markup)
    try:
        async with aiohttp.ClientSession() as s:
            async with s.post(url, json=payload, timeout=_TIMEOUT) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    logger.warning("Telegram hata %d: %s", resp.status, body[:200])
                    return None
                data = await resp.json()
                return data.get("result", {}).get("message_id")
    except Exception as exc:
        logger.warning("Telegram gönderilemedi: %s", exc)
        return None


async def answer_callback(
    bot_token: str,
    callback_query_id: str,
    text: str = "",
    show_alert: bool = False,
) -> None:
    """Inline klavye butonuna basılınca kullanıcıya bildirim gönderir."""
    if not bot_token:
        return
    url = f"https://api.telegram.org/bot{bot_token}/answerCallbackQuery"
    payload = {"callback_query_id": callback_query_id, "text": text, "show_alert": show_alert}
    try:
        async with aiohttp.ClientSession() as s:
            async with s.post(url, json=payload, timeout=_TIMEOUT) as resp:
                if resp.status != 200:
                    logger.debug("answerCallback hata %d", resp.status)
    except Exception as exc:
        logger.debug("answerCallback gönderilemedi: %s", exc)


async def set_commands(
    bot_token: str,
    commands: list[dict],
    scope: dict | None = None,
) -> bool:
    """setMyCommands — Telegram "/" menüsünü ayarlar.

    commands: [{"command": "durum", "description": "Cluster özeti"}, ...]
    scope:    {"type": "chat", "chat_id": "..."}  — None = global
    """
    if not bot_token:
        return False
    url = f"https://api.telegram.org/bot{bot_token}/setMyCommands"
    payload: dict = {"commands": commands}
    if scope:
        payload["scope"] = scope
    try:
        async with aiohttp.ClientSession() as s:
            async with s.post(url, json=payload, timeout=_TIMEOUT) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    logger.warning("setMyCommands hata %d: %s", resp.status, body[:200])
                    return False
                data = await resp.json()
                return bool(data.get("ok"))
    except Exception as exc:
        logger.warning("setMyCommands gönderilemedi: %s", exc)
        return False


async def get_updates(
    bot_token: str,
    offset: int,
    timeout: int = 1,
) -> list[dict]:
    """getUpdates — polling için. Telegram long-poll (timeout=1 ile kısa)."""
    if not bot_token:
        return []
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates"
    params = {
        "offset": offset,
        "timeout": timeout,
        "limit": 20,
        "allowed_updates": json.dumps(["message", "callback_query"]),
    }
    try:
        async with aiohttp.ClientSession() as s:
            async with s.get(
                url, params=params,
                timeout=aiohttp.ClientTimeout(total=timeout + 5),
            ) as resp:
                if resp.status != 200:
                    return []
                data = await resp.json()
                return data.get("result", []) if data.get("ok") else []
    except Exception as exc:
        logger.debug("getUpdates hatası: %s", exc)
        return []
