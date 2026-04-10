"""
Chat servisi — Pub/Sub altyapısı ve mesaj iş mantığını router'dan ayırır.

İçerir:
  • chat_key / publish_chat / update_viewer_count — altyapı yardımcıları
  • chat_pubsub_listener / moderation_pubsub_listener — arka plan görevleri
  • ChatService — WebSocket bağlantısının iş mantığı operasyonları

Dependency Injection:
    ChatService'in hiçbir metodu `AsyncSession` almaz; tüm state Redis'te tutulur.
    DB doğrulaması (kullanıcı/stream lookup) WebSocket bağlantısı sırasında doğrudan
    AsyncSessionLocal ile chat.py'de yapılır (WS protokol akışına özel).

Hata Yönetimi:
    Altyapı hataları (viewer count, history) → logger.warning (non-critical, WS açık kalır)
    Mesaj işleme hataları → logger.warning (döngü devam eder)
"""
import asyncio
import json
import uuid
from datetime import datetime, timezone

import redis.asyncio as aioredis
from sqlalchemy import select

from app.config import settings
from app.core.auto_mod import auto_mod
from app.core.logger import get_logger
from app.core.ws_manager import ws_manager, safe_send_json
from app.constants import ws_types as WS
from app.database import AsyncSessionLocal
from app.models.user import User
from app.services.moderation_service import mute_key, mod_key, MOD_CHANNEL
from app.utils.redis_client import get_redis

logger = get_logger(__name__)

_CHAT_CHANNEL = "chat_broadcast"
_MAX_HISTORY = 50


# ── Redis key ────────────────────────────────────────────────────────────────
def chat_key(stream_id: int) -> str:
    return f"chat:{stream_id}:messages"


# ── Pub/Sub yayın yardımcısı ─────────────────────────────────────────────────
async def publish_chat(stream_id: int, payload: dict) -> None:
    """Chat mesajını Redis Pub/Sub aracılığıyla tüm worker'lara yayar."""
    await ws_manager.publish(_CHAT_CHANNEL, f"chat:{stream_id}", payload)


# ── Viewer count ─────────────────────────────────────────────────────────────
async def update_viewer_count(room_name: str, stream_id: int, delta: int) -> None:
    """Redis'teki izleyici sayısını günceller ve tüm istemcilere yayınlar."""
    try:
        redis = await get_redis()
        key = f"live:viewers:{room_name}"
        if delta > 0:
            count = await redis.incr(key)
        else:
            count = await redis.decr(key)
            if count < 0:
                await redis.set(key, 0)
                count = 0
        await publish_chat(stream_id, {"type": WS.VIEWER_COUNT, "count": int(count)})
    except Exception:
        logger.error(
            "[CHAT] Viewer count güncellenemedi | room=%s stream_id=%s delta=%s",
            room_name, stream_id, delta, exc_info=True,
        )


# ── Pub/Sub dinleyicileri (arka plan görevleri) ──────────────────────────────
async def chat_pubsub_listener() -> None:
    """Her worker için tek seferlik başlatılan chat pub/sub dinleyicisi."""
    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(_CHAT_CHANNEL)
    logger.info("[CHAT PUBSUB] Dinleyici başladı (worker)")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
                topic = data.pop("_topic")
                asyncio.create_task(ws_manager.broadcast_local(topic, data))
            except Exception as exc:
                logger.warning("[CHAT PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(_CHAT_CHANNEL)
        await r.aclose()


async def moderation_pubsub_listener() -> None:
    """Her worker için moderasyon event dinleyicisi (muted/kicked/unmuted/promoted/demoted)."""
    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(MOD_CHANNEL)
    logger.info("[MOD PUBSUB] Dinleyici başladı (worker)")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
                await _dispatch_mod_event(data)
            except Exception as exc:
                logger.warning("[MOD PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(MOD_CHANNEL)
        await r.aclose()


async def _dispatch_mod_event(data: dict) -> None:
    """Moderasyon event verisini ilgili WebSocket topic'lerine dağıtır."""
    stream_id = int(data["_stream_id"])
    user_id = int(data["user_id"])
    event_type = data["type"]
    logger.info(
        "[MOD PUBSUB] EVENT ALINDI | type=%s stream_id=%s user_id=%s",
        event_type, stream_id, user_id,
    )
    if event_type == WS.MOD_PROMOTED:
        await ws_manager.broadcast_local(
            f"chat:{stream_id}",
            {
                "type": WS.MOD_PROMOTED,
                "user_id": user_id,
                "username": data.get("username"),
                "promoted_by": data.get("promoted_by"),
            },
        )
        await ws_manager.broadcast_local(
            f"chat:{stream_id}:u{user_id}",
            {"type": WS.MOD_PROMOTED_SELF, "promoted_by": data.get("promoted_by")},
        )
    elif event_type == WS.MOD_DEMOTED:
        await ws_manager.broadcast_local(
            f"chat:{stream_id}",
            {
                "type": WS.MOD_DEMOTED,
                "user_id": user_id,
                "username": data.get("username"),
                "demoted_by": data.get("demoted_by"),
            },
        )
        await ws_manager.broadcast_local(
            f"chat:{stream_id}:u{user_id}",
            {"type": WS.MOD_DEMOTED_SELF, "demoted_by": data.get("demoted_by")},
        )
    else:
        await ws_manager.broadcast_local(
            f"chat:{stream_id}:u{user_id}",
            {"type": event_type},
        )


# ── Servis sınıfı ────────────────────────────────────────────────────────────
class ChatService:
    """
    WebSocket chat bağlantısının iş mantığı operasyonlarını barındıran servis.

    DB bağımlılığı yoktur; tüm state Redis'te tutulur.
    WS protokol akışı (accept/close/receive döngüsü) chat.py router'ında kalır,
    business operasyonları (history, mute kontrolü, mesaj kalıcılığı) buraya taşınmıştır.

    Kullanım:
        svc = ChatService()
        history = await svc.load_history(stream_id)
        chat_msg = await svc.process_message(...)
    """

    # ── Bağlantı Başlangıcı ──────────────────────────────────────────────────
    async def load_history(self, stream_id: int) -> list:
        """Son _MAX_HISTORY mesajı Redis'ten okur."""
        redis = await get_redis()
        history_raw = await redis.lrange(chat_key(stream_id), -_MAX_HISTORY, -1)
        return [json.loads(m) for m in history_raw] if history_raw else []

    async def get_viewer_count(self, room_name: str) -> int:
        """Redis'ten mevcut izleyici sayısını okur."""
        redis = await get_redis()
        count_raw = await redis.get(f"live:viewers:{room_name}")
        return int(count_raw) if count_raw else 0

    async def get_mod_status(self, stream_id: int, user_id: int) -> bool:
        """Kullanıcının bu yayında moderatör olup olmadığını kontrol eder."""
        redis = await get_redis()
        return bool(await redis.sismember(mod_key(stream_id), str(user_id)))

    async def add_viewer(self, stream_id: int, room_name: str, username: str) -> None:
        """Viewer count'u artırır ve viewer_set'e ekler."""
        await update_viewer_count(room_name, stream_id, +1)
        try:
            redis = await get_redis()
            await redis.sadd(f"live:viewer_set:{stream_id}", username)
        except Exception as exc:
            logger.warning("[CHAT] viewer_set sadd başarısız | stream_id=%s | %s", stream_id, exc)

    async def remove_viewer(self, stream_id: int, room_name: str, username: str) -> None:
        """Viewer count'u azaltır ve viewer_set'ten çıkarır."""
        await update_viewer_count(room_name, stream_id, -1)
        try:
            redis = await get_redis()
            await redis.srem(f"live:viewer_set:{stream_id}", username)
        except Exception as exc:
            logger.warning("[CHAT] viewer_set srem başarısız | stream_id=%s | %s", stream_id, exc)

    # ── Shadowban cache yardımcısı ────────────────────────────────────────────
    async def is_shadowbanned(self, user_id: int) -> bool:
        """
        Kullanıcının shadowban durumunu Redis cache'den okur.
        Cache'de yoksa DB'den çekip 5 dakika boyunca cache'ler.
        """
        redis = await get_redis()
        cache_key = f"shadowban:{user_id}"
        cached = await redis.get(cache_key)
        if cached is not None:
            return cached == b"1" or cached == "1"

        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User.is_shadowbanned).where(User.id == user_id))
            row = result.scalar_one_or_none()
            banned = bool(row) if row is not None else False

        await redis.set(cache_key, "1" if banned else "0", ex=300)
        return banned

    # ── Mesaj İşle ───────────────────────────────────────────────────────────
    async def _check_muted(self, redis, stream_id: int, user_id: int) -> bool:
        """Kullanıcının bu yayında mute'lu olup olmadığını kontrol eder."""
        return bool(await redis.sismember(mute_key(stream_id), str(user_id)))

    async def _apply_content_filters(self, user_id: int, content: str) -> bool:
        """Shadowban veya küfür içeriyorsa True (mesaj gizlenecek) döner."""
        return await self.is_shadowbanned(user_id) or auto_mod.contains_profanity(content)

    async def _build_message_obj(
        self, redis, stream_id: int, user_id: int, username: str,
        profile_image_url: str | None, content: str, is_host: bool, is_hidden: bool,
    ) -> dict:
        """Mesaj sözlüğünü oluşturur; moderatör rozetini Redis'ten kontrol eder."""
        is_mod = bool(await redis.sismember(mod_key(stream_id), str(user_id)))
        return {
            "type": WS.MESSAGE,
            "id": str(uuid.uuid4())[:8],
            "username": username,
            "profile_image_url": profile_image_url,
            "content": content,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "is_mod": is_mod,
            "is_host": is_host,
            "is_hidden": is_hidden,
        }

    async def _persist_and_publish(
        self, redis, stream_id: int, chat_msg: dict, username: str
    ) -> None:
        """Mesajı Redis'e kaydeder; gizli değilse Pub/Sub ile yayınlar."""
        key = chat_key(stream_id)
        await redis.rpush(key, json.dumps(chat_msg))
        await redis.ltrim(key, -_MAX_HISTORY, -1)
        await redis.expire(key, 24 * 3600)

        if not chat_msg["is_hidden"]:
            await publish_chat(stream_id, chat_msg)
            logger.info("[CHAT] stream_id=%s user=%s | mesaj gönderildi", stream_id, username)
        else:
            logger.info(
                "[CHAT] stream_id=%s user=%s | ghost mesaj (shadowban veya küfür)",
                stream_id, username,
            )

    async def process_message(
        self,
        stream_id: int,
        user_id: int,
        username: str,
        profile_image_url: str | None,
        is_host: bool,
        content: str,
    ) -> dict | None:
        """
        Mesajı işler: mute → shadowban/auto-mod → mod rozeti → Redis → broadcast.

        Dönüş değerleri:
          None        → kullanıcı mute'lu (caller "muted" hatası gönderir)
          dict        → mesaj (is_hidden=True ise ghost; caller sadece gönderene yollar)
        """
        redis = await get_redis()

        if await self._check_muted(redis, stream_id, user_id):
            return None

        is_hidden = await self._apply_content_filters(user_id, content)
        chat_msg = await self._build_message_obj(
            redis, stream_id, user_id, username, profile_image_url, content, is_host, is_hidden
        )
        await self._persist_and_publish(redis, stream_id, chat_msg, username)
        return chat_msg
