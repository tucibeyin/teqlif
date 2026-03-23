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
  ws_manager.publish() → Redis channel'a yayınlar
  Her worker'ın pub/sub listener'ı Redis'ten alır
  → ws_manager.broadcast_local(topic, data) çağırır
  Bu sayede mesaj tüm worker'lardaki abonelere ulaşır.
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
                self._ws_topics.get(ws, set()).discard(topic)
                logger.debug(
                    "[WS GATEWAY] Ölü bağlantı temizlendi | topic=%s result=%s",
                    topic, result,
                )

        return alive

    async def publish(
        self,
        redis_channel: str,
        topic: str,
        payload: dict,
    ) -> None:
        """
        Mesajı Redis Pub/Sub aracılığıyla tüm yatay worker'lara yayar.

        Her worker'ın ilgili pub/sub dinleyicisi Redis'ten mesajı alır ve
        broadcast_local(topic, data) çağırarak kendi bağlantılarına dağıtır.

        Parametreler:
            redis_channel: Redis kanalı adı ("chat_broadcast" vb.)
            topic:         Hedef WS topic'i ("chat:299" vb.)
            payload:       İstemciye gönderilecek mesaj

        Hata durumunda loglayıp sessizce devam eder — publisher bloklanmaz.
        """
        try:
            redis = await get_redis()
            data = json.dumps({"_topic": topic, **payload})
            await redis.publish(redis_channel, data)
        except Exception as exc:
            logger.error(
                "[WS GATEWAY] Redis publish hatası | channel=%s topic=%s | %s",
                redis_channel, topic, exc, exc_info=True,
            )

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
