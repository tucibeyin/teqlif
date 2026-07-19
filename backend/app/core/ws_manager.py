"""
Global WebSocket Gateway — Merkezi Bağlantı Yöneticisi (Aşama 2)

Topic tabanlı birleşik WebSocket bağlantı yönetimi. Tüm WS tipleri
(chat, bildirim, DM) bu tekil gateway üzerinden yönetilir.

── Topic İsimlendirme Kuralı ────────────────────────────────────────────────
  chat:{stream_id}          — yayın sohbet odası  (tüm izleyicilere broadcast)
  chat:{stream_id}:u{uid}   — kullanıcıya özel kanal (moderasyon eventleri)
  notif:{user_id}           — bildirim bağlantısı
  dm:{user_id}              — DM (anlık mesaj) bağlantısı

── Kullanım Örnekleri ───────────────────────────────────────────────────────
  from app.core.ws_manager import ws_manager, safe_send_json

  # Bağlantı kaydı (accept() çağrısı dışarıda yapılmış olmalıdır)
  ws_manager.connect(websocket, "chat:42")
  ws_manager.connect(websocket, "chat:42:u7")  # aynı WS, ikinci topic

  # Bu worker'a yerel broadcast (paralel fan-out)
  await ws_manager.broadcast_local("chat:42", payload)

  # Redis üzerinden tüm worker'lara yayın
  await ws_manager.publish("chat_broadcast", "chat:42", payload)

  # Bağlantı sonlandırma (birden fazla topic)
  ws_manager.disconnect(websocket, "chat:42", "chat:42:u7")

  # Graceful shutdown (lifespan kapanışı)
  await ws_manager.shutdown()

── Yatay Ölçekleme (Multi-Worker) ──────────────────────────────────────────
  ws_manager.publish() → Redis Stream'e XADD yapar
  Her worker'ın stream_listener'ı kendi pozisyonundan XREAD eder
  → ws_manager.broadcast_local(topic, data) çağırır
  Bu sayede mesaj tüm worker'lardaki abonelere ulaşır.
  Pub/Sub'dan farkı: worker yeniden bağlandığında kaçırılan mesajlar replay edilir.
"""

import asyncio
import json
from typing import Dict, Set

from fastapi import WebSocket, WebSocketDisconnect

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)


# ── Güvenli Gönderim (Standart Yardımcı) ────────────────────────────────────
async def safe_send_json(ws: WebSocket, payload: dict) -> bool:
    """
    Bağlantı durumundan bağımsız güvenli JSON gönderimi.

    'Cannot call send once close message sent', 'WebSocketDisconnect' ve
    diğer kapanma sürecine ait hataları sessizce yakalar.
    Tüm WS endpoint'leri bu fonksiyonu kullanır — duplike try/except yok.

    Returns:
        True  — gönderim başarılı
        False — bağlantı kapalıydı veya hata oluştu
    """
    try:
        await ws.send_json(payload)
        return True
    except WebSocketDisconnect:
        return False
    except RuntimeError as exc:
        # "Cannot call send once close message sent" vb. durum hataları
        logger.debug("[WS GATEWAY] RuntimeError send sırasında (kapanıyor): %s", exc)
        return False
    except Exception as exc:
        logger.warning("[WS GATEWAY] send_json beklenmeyen hata: %s", exc)
        return False


# ── Merkezi Gateway ──────────────────────────────────────────────────────────
class GlobalWSManager:
    """
    Tüm WebSocket bağlantılarını topic tabanlı yöneten merkezi gateway.

    Temel Özellikler:
    - asyncio.gather ile paralel fan-out (eski ChatManager Aşama 3 mirasçısı)
    - Ölü bağlantıları broadcast sırasında otomatik temizler
    - Graceful shutdown: tüm açık bağlantıları 1001 ile kapatır
    - Redis publish() metodu ile yatay ölçekleme desteği
    - Aynı WS nesnesi birden fazla topic'e kaydedilebilir
    """

    def __init__(self) -> None:
        # topic → WebSocket seti  (broadcast yapısı)
        self._topics: Dict[str, Set[WebSocket]] = {}
        # WebSocket → topic seti  (graceful shutdown için reverse index)
        self._ws_topics: Dict[WebSocket, Set[str]] = {}

    # ── Bağlantı Yönetimi ─────────────────────────────────────────────────

    def connect(self, ws: WebSocket, topic: str) -> int:
        """
        WS'i bir topic'e kaydeder.
        accept() çağrısının DIŞARIDA — endpoint içinde — yapılmış olması gerekir.
        Aynı WS, farklı topic'ler için birden fazla kez çağrılabilir.

        Returns: topic'teki güncel abone sayısı.
        """
        self._topics.setdefault(topic, set()).add(ws)
        self._ws_topics.setdefault(ws, set()).add(topic)
        count = len(self._topics[topic])
        logger.debug("[WS GATEWAY] connect | topic=%s | abone=%s", topic, count)
        return count

    def disconnect(self, ws: WebSocket, *topics: str) -> None:
        """
        WS'i bir veya birden fazla topic'ten kaldırır.
        Tüm topic'lerden çıkarıldığında reverse index'ten de silinir.
        """
        for topic in topics:
            self._topics.get(topic, set()).discard(ws)
            self._ws_topics.get(ws, set()).discard(topic)
            logger.debug("[WS GATEWAY] disconnect | topic=%s", topic)
        # Hiçbir topic'e bağlı değilse reverse index'ten temizle
        if ws in self._ws_topics and not self._ws_topics[ws]:
            del self._ws_topics[ws]

    def subscriber_count(self, topic: str) -> int:
        """Topic'teki aktif abone sayısını döner (monitoring için)."""
        return len(self._topics.get(topic, set()))

    # ── Yayın (Broadcast) ─────────────────────────────────────────────────

    async def broadcast_local(self, topic: str, payload: dict) -> int:
        """
        Bu worker'daki topic abonelerine asyncio.gather ile paralel fan-out.

        - Snapshot alınır: iterasyon sırasında set değişmez
        - return_exceptions=True: tek kopuk bağlantı diğerlerini engellemez
        - Ölü bağlantılar otomatik temizlenir

        Returns: başarılı gönderim sayısı.
        """
        targets = list(self._topics.get(topic, set()))
        if not targets:
            return 0

        results = await asyncio.gather(
            *[safe_send_json(ws, payload) for ws in targets],
            return_exceptions=True,
        )

        alive = 0
        live_set = self._topics.get(topic, set())
        for ws, result in zip(targets, results):
            if result is True:
                alive += 1
            else:
                live_set.discard(ws)
                ws_topics = self._ws_topics.get(ws)
                if ws_topics is not None:
                    ws_topics.discard(topic)
                    if not ws_topics:
                        del self._ws_topics[ws]
                logger.debug(
                    "[WS GATEWAY] Ölü bağlantı temizlendi | topic=%s result=%s",
                    topic, result,
                )

        return alive

    async def publish(
        self,
        stream_name: str,
        topic: str,
        payload: dict,
    ) -> None:
        """
        Mesajı Redis Stream'e yazarak tüm yatay worker'lara yayar.

        Her worker'ın stream_listener'ı kendi okuma pozisyonundan XREAD eder
        ve broadcast_local(topic, data) çağırarak kendi bağlantılarına dağıtır.
        Pub/Sub'un aksine worker yeniden bağlandığında kaçırılan mesajlar
        position'dan itibaren replay edilir — kayıp mesaj olmaz.

        Parametreler:
            stream_name: Redis Stream adı ("dm_broadcast" vb.)
            topic:       Hedef WS topic'i ("dm:{user_id}" vb.)
            payload:     İstemciye gönderilecek mesaj

        Hata durumunda loglayıp sessizce devam eder — publisher bloklanmaz.
        """
        try:
            from app.core.stream_listener import STREAM_MAXLEN
            redis = await get_redis()
            data = json.dumps({"_topic": topic, **payload})
            await redis.xadd(stream_name, {"data": data}, maxlen=STREAM_MAXLEN, approximate=True)
        except Exception as exc:
            logger.error(
                "[WS GATEWAY] Redis stream yazma hatası | stream=%s topic=%s | %s",
                stream_name, topic, exc, exc_info=True,
            )

    # ── Call Event Replay (WS kayıp event recovery) ──────────────────────

    async def store_call_event(self, user_id: int, payload: dict) -> None:
        """
        Gelen arama eventini Redis sorted set'e kaydeder (score=Unix timestamp).
        TTL=90s: arama etkinlikleri bu pencerede yeniden teslim edilebilir.
        Bağlantı kopukluğu sırasında kaçırılan call_accepted/call_ended gibi
        kritik eventleri, yeniden bağlanmada replay_call_events ile gönderir.
        """
        import time
        try:
            redis = await get_redis()
            score = time.time()
            data = json.dumps({"_ts": score, **payload})
            key = f"call_events:{user_id}"
            await redis.zadd(key, {data: score})
            await redis.expire(key, 90)
            logger.debug("[WS GATEWAY] call_events stored | user_id=%s type=%s score=%s", user_id, payload.get("type"), score)
        except Exception as exc:
            logger.warning("[WS GATEWAY] call_events store FAILED | user_id=%s | %s", user_id, exc)

    async def replay_call_events(self, ws: "WebSocket", user_id: int, since_ts: float) -> int:
        """
        since_ts'den bu yana kaydedilen call_ eventleri yeniden gönderir.
        WS yeniden bağlandığında auth mesajındaki since_ts ile çağrılır.
        """
        try:
            redis = await get_redis()
            key = f"call_events:{user_id}"
            # since_ts'den BÜYÜK score'ları al (strictly greater — yinelemeyi önler)
            events_raw = await redis.zrangebyscore(key, f"({since_ts}", "+inf")
            count = 0
            for raw in events_raw:
                try:
                    event_payload = json.loads(raw)
                    event_payload.pop("_ts", None)
                    await safe_send_json(ws, event_payload)
                    count += 1
                except Exception:
                    pass
            if count > 0:
                logger.info(
                    "[WS GATEWAY] call_events REPLAYED | user_id=%s since_ts=%s count=%s",
                    user_id, since_ts, count,
                )
            return count
        except Exception as exc:
            logger.warning("[WS GATEWAY] replay_call_events FAILED | user_id=%s | %s", user_id, exc)
            return 0

    # ── DM Online Status (cross-worker VoIP push guard) ──────────────────
    #
    # subscriber_count() is local-only. In a multi-worker uvicorn setup the
    # iOS WS may be on Worker A while POST /calls/start lands on Worker B —
    # Worker B sees count=0 and fires the VoIP push, causing a foreground
    # native CallKit flash. These Redis-backed methods give a global view.

    _WS_DM_TTL = 90  # covers the ~35-40s ping-timeout reconnect window

    async def mark_dm_online(self, user_id: int) -> None:
        try:
            r = await get_redis()
            await r.setex(f"ws_dm_online:{user_id}", self._WS_DM_TTL, 1)
        except Exception as exc:
            logger.warning("[WS GATEWAY] mark_dm_online failed | user=%d | %s", user_id, exc)

    async def mark_dm_offline(self, user_id: int) -> None:
        try:
            r = await get_redis()
            await r.delete(f"ws_dm_online:{user_id}")
        except Exception as exc:
            logger.warning("[WS GATEWAY] mark_dm_offline failed | user=%d | %s", user_id, exc)

    async def is_dm_online(self, user_id: int) -> bool:
        """Local check first (fast path), then Redis for cross-worker accuracy."""
        if self.subscriber_count(f"dm:{user_id}") > 0:
            return True
        try:
            r = await get_redis()
            return bool(await r.exists(f"ws_dm_online:{user_id}"))
        except Exception as exc:
            logger.warning("[WS GATEWAY] is_dm_online failed | user=%d | %s", user_id, exc)
            return False  # safe fallback: push gönder

    # ── Graceful Shutdown ─────────────────────────────────────────────────

    async def shutdown(self) -> None:
        """
        FastAPI lifespan kapanışında tüm açık WS bağlantılarını
        1001 (Going Away) koduyla güvenli biçimde kapatır.

        main.py lifespan'inde yield'dan sonra çağrılmalıdır:
            await ws_manager.shutdown()
        """
        all_ws = list(self._ws_topics.keys())
        if not all_ws:
            return

        logger.info(
            "[WS GATEWAY] Graceful shutdown başlatıldı | açık bağlantı=%s",
            len(all_ws),
        )

        async def _close_one(ws: WebSocket) -> None:
            try:
                await ws.close(code=1001)
            except Exception:
                pass  # Zaten kapalı olabilir — sessizce geç

        await asyncio.gather(
            *[_close_one(ws) for ws in all_ws],
            return_exceptions=True,
        )
        self._topics.clear()
        self._ws_topics.clear()
        logger.info("[WS GATEWAY] Graceful shutdown tamamlandı.")


# ── Uygulama Geneli Tekil Instance ───────────────────────────────────────────
ws_manager = GlobalWSManager()
