"""teqlif-agent — Telegram Alerter DI.

Modüller Telegram'a doğrudan bağımlı değil; bu katmanla loose-coupled:

  TelegramBot      — bot_token ile low-level ops (get_updates, answer_callback)
  TelegramAlerter  — tek bir kanala (chat_id) bağlı alert gönderici

Kullanım:
  bot     = TelegramBot(cfg.telegram_bot_token)
  prod    = bot.alerter(cfg.telegram_chat_id)
  staging = bot.alerter(cfg.staging_telegram_chat_id)

  # Modülde:
  await self._alerter.send("🔴 node1 — disk %90")

Testlerde TelegramAlerter yerine başka bir nesne inject edilebilir.
"""
from __future__ import annotations

from dataclasses import dataclass

import telegram as tg


@dataclass
class TelegramAlerter:
    """Belirli bir Telegram kanalına bağlı alert gönderici."""
    bot_token: str
    chat_id: str

    async def send(self, text: str, markup: dict | None = None) -> int | None:
        """Mesaj gönderir. markup verilirse inline klavye ekler."""
        return await tg.send(self.bot_token, self.chat_id, text, reply_markup=markup)


@dataclass
class TelegramBot:
    """Channel bağımsız Telegram bot operasyonları."""
    bot_token: str

    def alerter(self, chat_id: str) -> TelegramAlerter:
        """Bu bot ile verilen channel'a bağlı bir alerter üretir."""
        return TelegramAlerter(bot_token=self.bot_token, chat_id=chat_id)

    async def get_updates(self, offset: int) -> list[dict]:
        return await tg.get_updates(self.bot_token, offset)

    async def answer_callback(
        self,
        cb_id: str,
        text: str = "",
        show_alert: bool = False,
    ) -> None:
        await tg.answer_callback(self.bot_token, cb_id, text, show_alert)
