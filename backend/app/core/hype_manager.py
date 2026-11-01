"""
Hype Manager V2 — Redis-backed, tüm Uvicorn worker'larında tutarlı.

Sorun (SRE-30): Eski sürüm tüm state'i Python process belleğinde
tutuyordu. 8 Uvicorn worker = 8 farklı skor → izleyici ekranında jitter.

Çözüm: State tamamen Redis'e taşındı.
  - Skor:     live:hype:score:{sid}            (float string)
  - Cooldown: live:hype:cd:{sid}:{uid}         (TTL = 10s)
  - Alert:    live:hype:alerted:{sid}          (TTL = 120s)
  - Highlight live:hype:hl:{sid}               (NX flag, remove_stream temizler)
  - Decay lock: live:hype:decay_lock           (TTL = 5s, tek worker çalışır)

Manipülasyon önleme:
  1. Kullanıcı başına rate limit: aynı kullanıcı 10 saniyede bir kez katkı yapabilir.
  2. Katkı tavanı: tek mesajdan max 10 puan alınır, kaç kelime yazılırsa yazılsın.
  3. √İzleyici normalizasyonu: katkı etkin puanı √(izleyici_sayısı) ile bölünür.

Sönümleme: 5 saniyede -5 puan — yalnızca distributed lock kazanan worker çalıştırır.
Host uyarısı: skor ≥ 80 VE son 2 dakikada uyarı verilmediyse.
"""

from __future__ import annotations

import asyncio

from app.core.logger import get_logger

logger = get_logger(__name__)

_DECAY_INTERVAL_SECS  = 5
_DECAY_AMOUNT         = 5.0
_ALERT_THRESHOLD      = 80.0
_ALERT_COOLDOWN_SECS  = 120
_SCORE_MIN            = 0.0
_SCORE_MAX            = 100.0
_USER_COOLDOWN_SECS   = 10
_CONTRIBUTION_CAP     = 10
_HIGHLIGHT_THRESHOLD  = 90.0
# Decay lock TTL = 1 interval; ilk acquire eden worker döngüyü monopolize eder.
# Worker çökerse TTL süresi dolunca bir diğeri devralır.
_DECAY_LOCK_TTL_MS    = _DECAY_INTERVAL_SECS * 1000


# Lua: delta ekle, 0–100 arasında sınırla, yeni skoru döndür.
_LUA_ADD_DELTA = """
local key  = KEYS[1]
local delta = tonumber(ARGV[1])
local cur   = tonumber(redis.call('GET', key) or '0')
local new   = cur + delta
if new < 0   then new = 0   end
if new > 100 then new = 100 end
redis.call('SET', key, tostring(new))
return tostring(new)
"""

# Lua: decay miktarını çıkar, 0'ın altına düşürme, yeni skoru döndür.
_LUA_DECAY = """
local key    = KEYS[1]
local amount = tonumber(ARGV[1])
local cur    = tonumber(redis.call('GET', key) or '0')
local new    = cur - amount
if new < 0 then new = 0 end
redis.call('SET', key, tostring(new))
return tostring(new)
"""


class HypeManager:
    """Redis-backed hype score manager — N Uvicorn worker'da cluster-safe singleton."""

    def __init__(self) -> None:
        self._decay_task: asyncio.Task | None = None

    # ── Skor işlemleri ──────────────────────────────────────────────────────────

    async def get_score(self, stream_id: int) -> float:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        val = await redis.get(f"live:hype:score:{stream_id}")
        return float(val) if val else 0.0

    async def add_delta(
        self,
        stream_id: int,
        delta: int,
        *,
        user_id: int | None = None,
        viewer_count: int = 1,
    ) -> float:
        """
        Skoru günceller ve yeni skoru döner.

        user_id verilirse: rate limit + katkı tavanı + √izleyici normalizasyonu uygulanır.
        Verilmezse: delta doğrudan eklenir.
        """
        from app.utils.redis_client import get_redis
        redis = await get_redis()

        if user_id is not None:
            # 1. Rate limit — SETNX ile atomik; key zaten varsa katkı reddedilir
            cd_key = f"live:hype:cd:{stream_id}:{user_id}"
            if not await redis.set(cd_key, "1", nx=True, ex=_USER_COOLDOWN_SECS):
                val = await redis.get(f"live:hype:score:{stream_id}")
                return float(val) if val else 0.0

            # 2. Katkı tavanı
            sign = 1 if delta >= 0 else -1
            capped = sign * min(abs(delta), _CONTRIBUTION_CAP)

            # 3. √İzleyici normalizasyonu
            effective = capped / max(1.0, viewer_count ** 0.5)
        else:
            effective = float(delta)

        result = await redis.eval(
            _LUA_ADD_DELTA,
            1,
            f"live:hype:score:{stream_id}",
            str(effective),
        )
        return float(result)

    async def should_alert(self, stream_id: int) -> bool:
        score = await self.get_score(stream_id)
        if score < _ALERT_THRESHOLD:
            return False
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        return await redis.get(f"live:hype:alerted:{stream_id}") is None

    async def mark_alerted(self, stream_id: int) -> None:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        await redis.set(f"live:hype:alerted:{stream_id}", "1", ex=_ALERT_COOLDOWN_SECS)

    async def should_highlight(self, stream_id: int, new_score: float) -> bool:
        """
        Oda için ilk kez 90 barajı aşıldıysa True döner (NX flag set eder).
        Sonraki çağrılar ve diğer worker'lar her zaman False alır.
        """
        if new_score < _HIGHLIGHT_THRESHOLD:
            return False
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        acquired = await redis.set(f"live:hype:hl:{stream_id}", "1", nx=True)
        return bool(acquired)

    async def remove_stream(self, stream_id: int) -> None:
        """Yayın bitince Redis'teki hype state'ini temizle."""
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        await redis.delete(
            f"live:hype:score:{stream_id}",
            f"live:hype:hl:{stream_id}",
            f"live:hype:alerted:{stream_id}",
        )

    # ── Decay (sönümleme) döngüsü ───────────────────────────────────────────────

    async def _decay_loop(self) -> None:
        from app.constants import ws_types as WS
        from app.use_cases.chat.chat_utils import publish_chat
        from app.utils.redis_client import get_redis

        while True:
            await asyncio.sleep(_DECAY_INTERVAL_SECS)
            redis = await get_redis()

            # Distributed lock: yalnızca lock'u kazanan worker decay'i çalıştırır.
            # Diğer 7 worker bu döngüde sadece sleep yapar.
            acquired = await redis.set(
                "live:hype:decay_lock", "1",
                nx=True, px=_DECAY_LOCK_TTL_MS,
            )
            if not acquired:
                continue

            try:
                keys = [k async for k in redis.scan_iter("live:hype:score:*")]
                for key in keys:
                    try:
                        stream_id = int(key.split(":")[-1])
                    except (ValueError, IndexError):
                        continue

                    val = await redis.get(key)
                    if val is None:
                        continue
                    if float(val) <= 0.0:
                        await redis.delete(key)
                        continue

                    new_score = float(
                        await redis.eval(_LUA_DECAY, 1, key, str(_DECAY_AMOUNT))
                    )

                    try:
                        await publish_chat(stream_id, {
                            "type": WS.HYPE_UPDATE,
                            "score": round(new_score),
                        })
                    except Exception as exc:
                        logger.warning(
                            "[Hype] Decay broadcast başarısız | stream=%s | %s", stream_id, exc,
                        )
            except Exception as exc:
                logger.warning("[Hype] Decay loop hatası: %s", exc)

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
