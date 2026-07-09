from typing import List

import asyncio
import json
import redis
import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func, or_, and_
from app.config import settings
from app.database import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.message import DirectMessage
from app.models.block import UserBlock
from app.schemas.message import MessageOut, ConversationOut, SendMessageIn
from app.schemas.notification import UnreadCountOut
from app.utils.auth import get_current_user, decode_token
from app.routers.notifications import push_notification
from app.core.auto_mod import analyze_text_all
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/messages", tags=["messages"])

_DM_CHANNEL = "dm_broadcast"


async def _broadcast_dm(user_id: int, payload: dict) -> None:
    """Push a DM payload to all workers via Redis pub/sub."""
    await ws_manager.publish(_DM_CHANNEL, f"dm:{user_id}", payload)


async def dm_pubsub_listener() -> None:
    """Per-worker background task that delivers DM broadcasts from Redis."""
    delay = 1.0
    while True:
        r = aioredis.from_url(settings.redis_url, decode_responses=True)
        pubsub = r.pubsub()
        keepalive_task: asyncio.Task | None = None
        try:
            await pubsub.subscribe(_DM_CHANNEL)
            logger.info("[DM PUBSUB] Dinleyici başladı (worker)")
            delay = 1.0

            async def _keepalive(ps: aioredis.client.PubSub, conn: aioredis.Redis) -> None:
                while True:
                    await asyncio.sleep(25)
                    try:
                        await ps.ping()
                    except Exception:
                        try:
                            await conn.aclose()
                        except Exception:
                            pass
                        break

            keepalive_task = asyncio.create_task(_keepalive(pubsub, r))

            while True:
                try:
                    async for message in pubsub.listen():
                        if message["type"] in ("pong", "subscribe", "unsubscribe"):
                            continue
                        if message["type"] != "message":
                            continue
                        try:
                            data = json.loads(message["data"])
                            topic = data.pop("_topic")
                            asyncio.create_task(ws_manager.broadcast_local(topic, data))
                        except Exception as exc:
                            logger.warning("[DM PUBSUB] Mesaj işleme hatası: %s", exc)
                    break
                except redis.exceptions.TimeoutError:
                    continue
                except Exception:
                    raise
        except asyncio.CancelledError:
            if keepalive_task:
                keepalive_task.cancel()
            await pubsub.unsubscribe(_DM_CHANNEL)
            await r.aclose()
            return
        except Exception as exc:
            logger.error("[DM PUBSUB] Bağlantı hatası, %ss sonra yeniden denenecek: %s", delay, exc)
        finally:
            if keepalive_task and not keepalive_task.done():
                keepalive_task.cancel()
            try:
                await pubsub.unsubscribe(_DM_CHANNEL)
                await r.aclose()
            except Exception:
                pass
        await asyncio.sleep(delay)
        delay = min(delay * 2, 30.0)


@router.get("/conversations", response_model=List[ConversationOut])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # SQL ile konuşma başına en son mesajı bul (tüm mesajları Python'a çekmez)
    conv_subq = (
        select(
            func.least(DirectMessage.sender_id, DirectMessage.receiver_id).label("min_uid"),
            func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id).label("max_uid"),
            func.max(DirectMessage.created_at).label("max_at"),
        )
        .where(
            or_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == uid)
        )
        .group_by(
            func.least(DirectMessage.sender_id, DirectMessage.receiver_id),
            func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id),
        )
        .subquery()
    )

    msgs_result = await db.execute(
        select(DirectMessage)
        .join(
            conv_subq,
            and_(
                func.least(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.min_uid,
                func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.max_uid,
                DirectMessage.created_at == conv_subq.c.max_at,
            ),
        )
        .where(or_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == uid))
        .order_by(DirectMessage.created_at.desc())
    )
    latest_msgs = msgs_result.scalars().all()

    if not latest_msgs:
        return []

    other_ids = [m.receiver_id if m.sender_id == uid else m.sender_id for m in latest_msgs]

    # Kullanıcı bilgileri ve okunmamış sayıları paralel çek
    users_result, unread_result = await asyncio.gather(
        db.execute(select(User).where(User.id.in_(other_ids))),
        db.execute(
            select(DirectMessage.sender_id, func.count().label("cnt"))
            .where(
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,  # noqa: E712
            )
            .group_by(DirectMessage.sender_id)
        ),
    )
    users_map = {u.id: u for u in users_result.scalars().all()}
    unread_map = {row.sender_id: row.cnt for row in unread_result}

    conversations = []
    for msg in latest_msgs:
        other_id = msg.receiver_id if msg.sender_id == uid else msg.sender_id
        other_user = users_map.get(other_id)
        if not other_user:
            continue
        conversations.append(
            ConversationOut(
                user_id=other_id,
                username=other_user.username,
                full_name=other_user.full_name,
                last_message=msg.content,
                last_at=msg.created_at,
                unread_count=unread_map.get(other_id, 0),
            )
        )

    return conversations


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_dm_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(func.count()).where(
            DirectMessage.receiver_id == current_user.id,
            DirectMessage.is_read == False,  # noqa: E712
        )
    )
    count = result.scalar_one()
    return UnreadCountOut(count=count)


@router.get("/{other_user_id}", response_model=List[MessageOut])
async def get_messages(
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # Check other user exists
    other_result = await db.execute(select(User).where(User.id == other_user_id))
    other_user = other_result.scalar_one_or_none()
    if not other_user:
        raise NotFoundException("Kullanıcı bulunamadı")

    # Fetch last 100 messages between the two users
    result = await db.execute(
        select(DirectMessage)
        .where(
            or_(
                and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_user_id),
                and_(DirectMessage.sender_id == other_user_id, DirectMessage.receiver_id == uid),
            )
        )
        .order_by(DirectMessage.created_at.asc())
        .limit(100)
    )
    messages = result.scalars().all()

    # Mark received messages as read and notify the sender
    result_update = await db.execute(
        update(DirectMessage)
        .where(
            DirectMessage.sender_id == other_user_id,
            DirectMessage.receiver_id == uid,
            DirectMessage.is_read == False,  # noqa: E712
        )
        .values(is_read=True)
        .returning(DirectMessage.id)
    )
    read_ids = [row[0] for row in result_update.fetchall()]
    await db.commit()
    if read_ids:
        await _broadcast_dm(other_user_id, {"type": "messages_read", "by_user_id": uid})

    # Build sender username map
    sender_ids = {m.sender_id for m in messages}
    users_result = await db.execute(select(User).where(User.id.in_(sender_ids)))
    users_map = {u.id: u for u in users_result.scalars().all()}

    output = []
    for msg in messages:
        sender = users_map.get(msg.sender_id)
        output.append(
            MessageOut(
                id=msg.id,
                sender_id=msg.sender_id,
                receiver_id=msg.receiver_id,
                sender_username=sender.username if sender else "",
                content=msg.content,
                is_read=msg.is_read,
                created_at=msg.created_at,
            )
        )
    return output


@router.post("/send", response_model=MessageOut)
async def send_message(
    data: SendMessageIn,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # Check receiver exists
    recv_result = await db.execute(select(User).where(User.id == data.receiver_id))
    receiver = recv_result.scalar_one_or_none()
    if not receiver:
        raise NotFoundException("Alıcı bulunamadı")

    if data.receiver_id == uid:
        raise BadRequestException("Kendinize mesaj gönderemezsiniz")

    # Engelleme kontrolü (iki yönlü)
    block_exists = await db.scalar(
        select(UserBlock).where(
            or_(
                and_(UserBlock.blocker_id == uid, UserBlock.blocked_id == data.receiver_id),
                and_(UserBlock.blocker_id == data.receiver_id, UserBlock.blocked_id == uid),
            )
        )
    )
    if block_exists:
        raise ForbiddenException("Bu kullanıcıyla mesajlaşamazsınız")

    # Auto-mod: içerik tüm dillerde kontrol edilir (zero-latency, DB öncesi)
    is_shadowbanned = analyze_text_all(data.content)

    msg = DirectMessage(
        sender_id=uid,
        receiver_id=data.receiver_id,
        listing_id=data.listing_id,
        content=data.content,
        is_shadowbanned=is_shadowbanned,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    out = MessageOut(
        id=msg.id,
        sender_id=msg.sender_id,
        receiver_id=msg.receiver_id,
        sender_username=current_user.username,
        content=msg.content,
        is_read=msg.is_read,
        created_at=msg.created_at,
    )

    dm_payload = {
        "type": "message",
        "id": msg.id,
        "sender_id": msg.sender_id,
        "receiver_id": msg.receiver_id,
        "sender_username": current_user.username,
        "content": msg.content,
        "is_read": msg.is_read,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }
    # Shadowbanned mesaj sadece gönderene görünür; alıcıya broadcast yapılmaz
    if not is_shadowbanned:
        await _broadcast_dm(data.receiver_id, dm_payload)
    await _broadcast_dm(uid, dm_payload)

    if is_shadowbanned:
        logger.info(
            "[AUTO_MOD] DM shadowban | sender_id=%s receiver_id=%s msg_id=%s",
            uid, data.receiver_id, msg.id,
        )

    # Create notification for receiver
    await push_notification(
        data.receiver_id,
        {
            "type": "message",
            "title": f"@{current_user.username} size mesaj gönderdi",
            "body": data.content[:100],
            "related_id": uid,
            "sender_username": current_user.username,
            "sender_image_url": current_user.profile_image_thumb_url,
        },
        pref_key="messages",
    )

    return out


@router.websocket("/ws")
async def messages_ws(websocket: WebSocket):
    # ── 1. Bağlantıyı kabul et (token URL'de taşınmaz) ───────────────────────
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error("[DM WS] accept() başarısız | %s", exc, exc_info=True)
        return

    # ── 2. İlk mesajdan token al (5s timeout) ────────────────────────────────
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        token = raw.get("token", "") if isinstance(raw, dict) else ""
    except WebSocketDisconnect:
        return
    except (asyncio.TimeoutError, Exception):
        try:
            await websocket.close(code=4001)
        except Exception:
            pass
        return

    user_id = decode_token(token)
    if not user_id:
        logger.warning("[DM WS] Geçersiz token, bağlantı kapatıldı")
        try:
            await websocket.close(code=4001)
        except Exception:
            pass
        return

    # ── 3. DB doğrulama ───────────────────────────────────────────────────────
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or not user.is_active:
                try:
                    await websocket.close(code=4001)
                except Exception:
                    pass
                return
    except Exception as exc:
        logger.error("[DM WS] DB doğrulama hatası | user_id=%s | %s", user_id, exc, exc_info=True)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
        return

    # ── 4. Eş zamanlı oturum koruması ─────────────────────────────────────────
    session_count = await register_ws_session(user_id)
    if session_count > MAX_CONCURRENT_SESSIONS:
        await release_ws_session(user_id)
        try:
            await websocket.close(code=4008)
        except Exception:
            pass
        logger.warning(
            "[DM WS] Eş zamanlı oturum limiti aşıldı | user_id=%s | count=%s limit=%s",
            user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    ws_manager.connect(websocket, f"dm:{user_id}")
    ws_manager.connect(websocket, "global")   # feed eventleri (stream_ended vb.)
    logger.info("[DM WS] BAĞLANDI | user_id=%s", user_id)

    try:
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
                if text.strip() == "ping":
                    await websocket.send_text("pong")
                else:
                    try:
                        import json as _json
                        msg = _json.loads(text)
                        if isinstance(msg, dict) and msg.get("type") == "typing":
                            target_id = msg.get("target_user_id")
                            if isinstance(target_id, int):
                                await _broadcast_dm(target_id, {
                                    "type": "typing",
                                    "sender_id": user_id,
                                })
                    except (ValueError, TypeError):
                        pass
            except asyncio.TimeoutError:
                logger.warning("[DM WS] İstemci ping timeout | user_id=%s", user_id)
                break
            except WebSocketDisconnect:
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[DM WS] HATA | user_id=%s | %s", user_id, exc)
    finally:
        ws_manager.disconnect(websocket, f"dm:{user_id}", "global")
        await release_ws_session(user_id)
        logger.info("[DM WS] AYRILDI | user_id=%s", user_id)
