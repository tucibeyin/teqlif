from typing import List

import asyncio
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func, or_, and_
from app.database import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.message import DirectMessage
from app.models.block import UserBlock
from app.schemas.message import MessageOut, ConversationOut, SendMessageIn
from app.schemas.notification import UnreadCountOut
from app.utils.auth import get_current_user, decode_token
from app.routers.notifications import push_notification
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/messages", tags=["messages"])

async def _broadcast_dm(user_id: int, payload: dict) -> None:
    """Push a DM payload to all active WS connections for the given user."""
    await ws_manager.broadcast_local(f"dm:{user_id}", payload)


@router.get("/conversations", response_model=List[ConversationOut])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # Get all messages involving current user
    result = await db.execute(
        select(DirectMessage)
        .where(
            or_(
                DirectMessage.sender_id == uid,
                DirectMessage.receiver_id == uid,
            )
        )
        .order_by(DirectMessage.created_at.desc())
    )
    all_msgs = result.scalars().all()

    # Build conversation map: other_user_id -> latest message
    seen: dict = {}
    for msg in all_msgs:
        other_id = msg.receiver_id if msg.sender_id == uid else msg.sender_id
        if other_id not in seen:
            seen[other_id] = msg

    if not seen:
        return []

    # Fetch user info for each other user
    other_ids = list(seen.keys())
    users_result = await db.execute(select(User).where(User.id.in_(other_ids)))
    users_map = {u.id: u for u in users_result.scalars().all()}

    # Count unread messages per conversation (sent by other to me, not read)
    unread_result = await db.execute(
        select(DirectMessage.sender_id, func.count().label("cnt"))
        .where(
            DirectMessage.receiver_id == uid,
            DirectMessage.is_read == False,  # noqa: E712
        )
        .group_by(DirectMessage.sender_id)
    )
    unread_map = {row.sender_id: row.cnt for row in unread_result}

    conversations = []
    for other_id, last_msg in seen.items():
        other_user = users_map.get(other_id)
        if not other_user:
            continue
        conversations.append(
            ConversationOut(
                user_id=other_id,
                username=other_user.username,
                full_name=other_user.full_name,
                last_message=last_msg.content,
                last_at=last_msg.created_at,
                unread_count=unread_map.get(other_id, 0),
            )
        )

    # Sort by last message time descending
    conversations.sort(key=lambda c: c.last_at, reverse=True)
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

    # Mark received messages as read
    await db.execute(
        update(DirectMessage)
        .where(
            DirectMessage.sender_id == other_user_id,
            DirectMessage.receiver_id == uid,
            DirectMessage.is_read == False,  # noqa: E712
        )
        .values(is_read=True)
    )
    await db.commit()

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

    msg = DirectMessage(
        sender_id=uid,
        receiver_id=data.receiver_id,
        content=data.content,
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

    # Broadcast to receiver's DM WebSocket if connected
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
    await _broadcast_dm(data.receiver_id, dm_payload)
    # Also send back to sender so their WS updates
    await _broadcast_dm(uid, dm_payload)

    # Create notification for receiver
    await push_notification(
        data.receiver_id,
        {
            "type": "message",
            "title": f"@{current_user.username} size mesaj gönderdi",
            "body": data.content[:100],
            "related_id": uid,
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
    except (asyncio.TimeoutError, Exception):
        await websocket.close(code=4001)
        return

    user_id = decode_token(token)
    if not user_id:
        logger.warning("[DM WS] Geçersiz token, bağlantı kapatıldı")
        await websocket.close(code=4001)
        return

    # ── 3. DB doğrulama ───────────────────────────────────────────────────────
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or not user.is_active:
                await websocket.close(code=4001)
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
        await websocket.close(code=4008)
        logger.warning(
            "[DM WS] Eş zamanlı oturum limiti aşıldı | user_id=%s | count=%s limit=%s",
            user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    ws_manager.connect(websocket, f"dm:{user_id}")
    logger.info("[DM WS] BAĞLANDI | user_id=%s", user_id)

    try:
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
                if text.strip() == "ping":
                    await websocket.send_text("pong")
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
        ws_manager.disconnect(websocket, f"dm:{user_id}")
        await release_ws_session(user_id)
        logger.info("[DM WS] AYRILDI | user_id=%s", user_id)
