"""
Hype Manager — Oda bazlı anlık Hype Skoru yönetimi.

Manipülasyon önleme:
  1. Kullanıcı başına rate limit: aynı kullanıcı 10 saniyede bir kez katkı yapabilir.
  2. Katkı tavanı: tek mesajdan max 10 puan alınır, kaç kelime yazılırsa yazılsın.
  3. √İzleyici normalizasyonu: katkı etkin puanı √(izleyici_sayısı) ile bölünür.
     → 1 izleyici: tam puan | 100 izleyici: 1/10 puan | 1000 izleyici: ~1/32 puan
     → Kalabalık bir oda; gerçek kitle coşkusu olmadan 100'e ulaşamaz.

Sönümleme: 5 saniyede -5 puan (izleyiciden bağımsız, sabit).
Host uyarısı: skor ≥ 80 VE son 2 dakikada uyarı verilmediyse.
"""

from __future__ import annotations

import asyncio
import time
from datetime import datetime, timedelta, timezone

from app.core.logger import get_logger

logger = get_logger(__name__)

_DECAY_INTERVAL_SECS         = 5       # sönümleme döngüsü frekansı
_DECAY_AMOUNT                = 5.0     # her döngüde düşürülecek puan
_ALERT_THRESHOLD             = 80.0    # host uyarısı eşiği
_ALERT_COOLDOWN_SECS         = 120     # aynı odaya tekrar uyarı göndermeden bekleme
_SCORE_MIN                   = 0.0
_SCORE_MAX                   = 100.0

# Manipülasyon önleme
_USER_COOLDOWN_SECS          = 10      # kullanıcı başına katkı aralığı
_CONTRIBUTION_CAP            = 10      # tek mesajdan max katkı (normalizasyon öncesi)


class HypeManager:
    """Singleton — `from app.core.hype_manager import hype_manager` ile kullanılır."""

    def __init__(self) -> None:
        self._scores:         dict[int, float]              = {}
        self._last_alert:     dict[int, datetime]           = {}
        # (stream_id, user_id) → son katkı zamanı (monotonic saniye)
        self._user_ts:        dict[tuple[int, int], float]  = {}
        self._decay_task: asyncio.Task | None               = None

    # ── Skor işlemleri ──────────────────────────────────────────────────────────

    def get_score(self, stream_id: int) -> float:
        return self._scores.get(stream_id, 0.0)

    def add_delta(
        self,
        stream_id: int,
        delta: int,
        *,
        user_id: int | None = None,
        viewer_count: int = 1,
    ) -> float:
        """
        Skoru günceller ve yeni skoru döner.

        user_id verilirse kullanıcı rate limit + tavan + normalizasyon uygulanır.
        Verilmezse (eski çağrılar için geriye uyumlu) delta doğrudan eklenir.
        """
        if user_id is not None:
            # 1. Rate limit — aynı kullanıcı 10 saniyede bir katkı yapabilir
            now = time.monotonic()
            key = (stream_id, user_id)
            if now - self._user_ts.get(key, 0.0) < _USER_COOLDOWN_SECS:
                return self._scores.get(stream_id, 0.0)
            self._user_ts[key] = now

            # 2. Katkı tavanı — çok fazla hype kelimesi yazılsa da üst sınır
            sign = 1 if delta >= 0 else -1
            capped = sign * min(abs(delta), _CONTRIBUTION_CAP)

            # 3. √İzleyici normalizasyonu — kalabalık odada tek kişi etkisiz kalır
            normed = capped / max(1.0, viewer_count ** 0.5)
            effective = normed
        else:
            effective = float(delta)

        current = self._scores.get(stream_id, 0.0)
        new = min(_SCORE_MAX, max(_SCORE_MIN, current + effective))
        self._scores[stream_id] = new
        return new

    def should_alert(self, stream_id: int) -> bool:
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
        """Yayın bitince state + kullanıcı kayıtlarını temizle."""
        self._scores.pop(stream_id, None)
        self._last_alert.pop(stream_id, None)
        stale = [k for k in self._user_ts if k[0] == stream_id]
        for k in stale:
            del self._user_ts[k]

    # ── Decay (sönümleme) döngüsü ───────────────────────────────────────────────

    async def _decay_loop(self) -> None:
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
        if self._decay_task is None or self._decay_task.done():
            self._decay_task = asyncio.create_task(self._decay_loop())
            logger.info("[Hype] Sönümleme döngüsü başlatıldı.")

    def stop_decay(self) -> None:
        if self._decay_task and not self._decay_task.done():
            self._decay_task.cancel()
            self._decay_task = None
            logger.info("[Hype] Sönümleme döngüsü durduruldu.")


hype_manager = HypeManager()
