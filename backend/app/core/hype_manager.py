"""
Hype Manager — Oda bazlı anlık Hype Skoru yönetimi.

Her canlı yayın odası için bellekte (in-memory) 0-100 arası bir skor tutar.
Yeni mesajlardaki hype puanı skoru artırır; 5 saniyede bir -5 sönümleme uygulanır.
Skor değişimlerini WS üzerinden tüm izleyicilere broadcast eder.
Host uyarısı: skor >= 80 ve son 2 dakikada uyarı verilmediyse host'a özel event gönderilir.

Tasarım kararları:
- In-memory dict — Redis gerektirmez, ultra düşük gecikme.
- Decay loop AsyncIO task olarak FastAPI lifespan'inde çalışır.
- Çoklu uvicorn worker senaryosunda her process bağımsız state tutar (kabul edilebilir
  trade-off; gerçek zamanlı hype metriği yaklaşık olması yeterlidir).
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

from app.core.logger import get_logger

logger = get_logger(__name__)

_DECAY_INTERVAL_SECS = 5      # sönümleme döngüsü frekansı
_DECAY_AMOUNT        = 5.0    # her döngüde düşürülecek puan
_ALERT_THRESHOLD     = 80.0   # bu eşiği geçince host'a uyarı
_ALERT_COOLDOWN_SECS = 120    # aynı odaya tekrar uyarı göndermeden önce bekleme
_SCORE_MIN           = 0.0
_SCORE_MAX           = 100.0


class HypeManager:
    """Singleton — `from app.core.hype_manager import hype_manager` ile kullanılır."""

    def __init__(self) -> None:
        self._scores:     dict[int, float]    = {}   # stream_id → skor
        self._last_alert: dict[int, datetime] = {}   # stream_id → son uyarı zamanı
        self._decay_task: asyncio.Task | None = None

    # ── Skor işlemleri ──────────────────────────────────────────────────────

    def get_score(self, stream_id: int) -> float:
        return self._scores.get(stream_id, 0.0)

    def add_delta(self, stream_id: int, delta: int) -> float:
        """Mevcut skora delta ekler, 0-100 arasında sınırlar ve yeni skoru döner."""
        current = self._scores.get(stream_id, 0.0)
        new = min(_SCORE_MAX, max(_SCORE_MIN, current + delta))
        self._scores[stream_id] = new
        return new

    def should_alert(self, stream_id: int) -> bool:
        """Skor eşiğin üzerinde VE son uyarıdan bu yana cooldown geçtiyse True döner."""
        if self._scores.get(stream_id, 0.0) < _ALERT_THRESHOLD:
            return False
        last = self._last_alert.get(stream_id)
        if last:
            elapsed = (datetime.now(timezone.utc) - last).total_seconds()
            if elapsed < _ALERT_COOLDOWN_SECS:
                return False
        return True

    def mark_alerted(self, stream_id: int) -> None:
        self._last_alert[stream_id] = datetime.now(timezone.utc)

    def remove_stream(self, stream_id: int) -> None:
        """Yayın bitince state temizle."""
        self._scores.pop(stream_id, None)
        self._last_alert.pop(stream_id, None)

    # ── Decay (sönümleme) döngüsü ───────────────────────────────────────────

    async def _decay_loop(self) -> None:
        """Her 5 saniyede aktif odaların skorunu -5 düşürür ve broadcast eder."""
        # Döngü içinde import: circular import önlemi
        from app.constants import ws_types as WS
        from app.services.chat_service import publish_chat
        from app.core.ws_manager import ws_manager as _ws_manager

        while True:
            await asyncio.sleep(_DECAY_INTERVAL_SECS)
            for sid in list(self._scores.keys()):
                current = self._scores[sid]
                if current <= 0.0:
                    self._scores.pop(sid, None)
                    continue
                new_score = max(_SCORE_MIN, current - _DECAY_AMOUNT)
                self._scores[sid] = new_score

                # Aktif abone yoksa broadcast yapma
                topic = f"chat:{sid}"
                if _ws_manager.subscriber_count(topic) == 0:
                    continue

                try:
                    await publish_chat(sid, {
                        "type": WS.HYPE_UPDATE,
                        "score": round(new_score),
                    })
                except Exception as exc:
                    logger.warning("[Hype] Decay broadcast başarısız | stream=%s | %s", sid, exc)

    def start_decay(self) -> None:
        """FastAPI lifespan startup'ında çağrılır."""
        if self._decay_task is None or self._decay_task.done():
            self._decay_task = asyncio.create_task(self._decay_loop())
            logger.info("[Hype] Sönümleme döngüsü başlatıldı.")

    def stop_decay(self) -> None:
        """FastAPI lifespan shutdown'ında çağrılır."""
        if self._decay_task and not self._decay_task.done():
            self._decay_task.cancel()
            self._decay_task = None
            logger.info("[Hype] Sönümleme döngüsü durduruldu.")


# Singleton
hype_manager = HypeManager()
