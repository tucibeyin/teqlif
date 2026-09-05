from typing import List
import asyncio
import json

from fastapi import APIRouter, Depends, Form, Query, Request, UploadFile, File, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.enums import UserStatus
from app.core.rate_limit import limiter, get_user_id_or_ip
from app.database import get_db, AsyncSessionLocal, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.core.log_context import user_id_var
from app.models.user import User
from app.schemas.message import MessageOut, ConversationOut, SendMessageIn, MediaContentType
from app.schemas.notification import UnreadCountOut
from app.utils.auth import get_current_user, decode_token
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.message_thread import MessageThread
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager
from app.core.logger import get_logger
from app.services.dm_broadcast import broadcast_dm, DM_CHANNEL

from app.use_cases.messages.queries.get_conversations_query import GetConversationsQuery
from app.use_cases.messages.queries.get_unread_count_query import GetUnreadCountQuery
from app.use_cases.messages.queries.get_messages_query import GetMessagesQuery
from app.use_cases.messages.queries.list_message_requests_query import ListMessageRequestsQuery
from app.use_cases.messages.queries.get_thread_status_query import GetThreadStatusQuery
from app.services.relationship_service import RelationshipStateService
from app.use_cases.messages.commands.send_direct_message import SendDirectMessageCommand
from app.use_cases.messages.commands.send_media_message_command import SendMediaMessageCommand
from app.use_cases.messages.commands.delete_message_command import DeleteMessageCommand
from app.use_cases.messages.commands.delete_conversation_command import DeleteConversationCommand
from app.use_cases.messages.commands.accept_message_request_command import AcceptMessageRequestCommand
from app.use_cases.messages.commands.decline_message_request_command import DeclineMessageRequestCommand

logger = get_logger(__name__)
router = APIRouter(prefix="/api/messages", tags=["messages"])


async def dm_pubsub_listener() -> None:
    from app.core.stream_listener import stream_listener

    async def _on_message(data: dict) -> None:
        topic = data.pop("_topic")
        asyncio.create_task(ws_manager.broadcast_local(topic, data))

    await stream_listener(DM_CHANNEL, _on_message)


# ── Conversations ─────────────────────────────────────────────────────────────

@router.get("/conversations", response_model=List[ConversationOut])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetConversationsQuery(uow).execute(current_user.id)


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_dm_count(
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    count = await GetUnreadCountQuery(uow).execute(current_user.id)
    return UnreadCountOut(count=count)


@router.get("/thread/{other_user_id}/status")
async def get_thread_status(
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetThreadStatusQuery(uow).execute(current_user.id, other_user_id)


@router.get("/requests", response_model=List[ConversationOut])
async def list_message_requests(
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await ListMessageRequestsQuery(uow).execute(current_user.id)


# ── Messages ──────────────────────────────────────────────────────────────────

@router.get("/{other_user_id}", response_model=List[MessageOut])
async def get_messages(
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetMessagesQuery(uow).execute(current_user.id, other_user_id)


@router.post("/send", response_model=MessageOut)
async def send_message(
    data: SendMessageIn,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await SendDirectMessageCommand(uow).execute(
        sender_id=current_user.id,
        receiver_id=data.receiver_id,
        content=data.content,
        listing_id=data.listing_id,
        sender_username=current_user.username,
    )


@router.post("/upload", response_model=MessageOut)
@limiter.limit("30/minute", key_func=get_user_id_or_ip)
async def upload_media_message(
    request: Request,
    receiver_id: int = Form(...),
    content_type_field: MediaContentType = Form(..., alias="content_type"),
    duration_secs: int | None = Form(None),
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    data = await file.read()
    return await SendMediaMessageCommand(uow).execute(
        sender_id=current_user.id,
        receiver_id=receiver_id,
        content_type_field=content_type_field,
        data=data,
        file_content_type=file.content_type or "",
        original_filename=file.filename or "",
        duration_secs=duration_secs,
        sender_username=current_user.username,
    )


# ── Delete ────────────────────────────────────────────────────────────────────

@router.delete("/{message_id}", status_code=204)
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def delete_message(
    request: Request,
    message_id: int,
    scope: str = Query("everyone", pattern="^(me|everyone)$"),
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    await DeleteMessageCommand(uow).execute(message_id, current_user.id, scope)


@router.delete("/conversation/{other_user_id}", status_code=204)
@limiter.limit("5/minute", key_func=get_user_id_or_ip)
async def delete_conversation(
    request: Request,
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    await DeleteConversationCommand(uow).execute(current_user.id, other_user_id)


# ── Message Requests ──────────────────────────────────────────────────────────

@router.post("/requests/{requester_id}/accept", status_code=204)
async def accept_message_request(
    requester_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    await AcceptMessageRequestCommand(uow).execute(current_user.id, requester_id, current_user.username)


@router.post("/requests/{requester_id}/decline", status_code=204)
async def decline_message_request(
    requester_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    await DeclineMessageRequestCommand(uow).execute(current_user.id, requester_id)


class _CallPermissionBody(BaseModel):
    call_allowed: bool


@router.patch("/thread/{other_user_id}/call-permission", status_code=200)
async def update_call_permission(
    other_user_id: int,
    body: _CallPermissionBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_a = min(current_user.id, other_user_id)
    user_b = max(current_user.id, other_user_id)
    thread = await db.scalar(
        select(MessageThread).where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
            MessageThread.status == "accepted",
        )
    )
    if not thread:
        raise NotFoundException(code="THREAD_NOT_FOUND")
    if thread.initiator_id == current_user.id:
        raise ForbiddenException(code="CALL_PERMISSION_NOT_YOURS")

    thread.call_allowed = body.call_allowed
    await db.commit()

    state = await RelationshipStateService.recompute_and_cache(user_a, user_b, db)
    RelationshipStateService.broadcast(state)

    return {"call_allowed": thread.call_allowed}


# ── WebSocket (infrastructure — router'da kalır) ──────────────────────────────

@router.websocket("/ws")
async def messages_ws(websocket: WebSocket):
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error("[DM WS] accept() başarısız | %s", exc, exc_info=True)
        return

    since_ts: float | None = None
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        token = raw.get("token", "") if isinstance(raw, dict) else ""
        if isinstance(raw, dict) and "since_ts" in raw:
            try:
                since_ts = float(raw["since_ts"])
            except (ValueError, TypeError):
                since_ts = None
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
    user_id_var.set(str(user_id))

    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or user.status != UserStatus.ACTIVE:
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
    ws_manager.connect(websocket, "global")
    await ws_manager.mark_dm_online(user_id)
    logger.info("[DM WS] BAĞLANDI | user_id=%s since_ts=%s", user_id, since_ts)

    if since_ts is not None:
        try:
            replayed = await ws_manager.replay_call_events(websocket, user_id, since_ts)
            if replayed > 0:
                logger.info("[CALL_PROCESS][STATE] WS event replay | user_id=%s since_ts=%s replayed=%s", user_id, since_ts, replayed)
        except Exception as _replay_exc:
            logger.warning("[DM WS] call event replay failed | user_id=%s | %s", user_id, _replay_exc)

    try:
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
                if text.strip() == "ping":
                    await websocket.send_text("pong")
                    await ws_manager.mark_dm_online(user_id)
                else:
                    try:
                        msg = json.loads(text)
                        if isinstance(msg, dict):
                            msg_type = msg.get("type")
                            if msg_type == "typing":
                                target_id = msg.get("target_user_id")
                                if isinstance(target_id, int):
                                    await broadcast_dm(target_id, {
                                        "type": "typing",
                                        "sender_id": user_id,
                                    })
                            elif msg_type == "typing_stopped":
                                target_id = msg.get("target_user_id")
                                if isinstance(target_id, int):
                                    await broadcast_dm(target_id, {
                                        "type": "typing_stopped",
                                        "sender_id": user_id,
                                    })
                            elif msg_type == "call_incoming_ack":
                                call_id = msg.get("call_id")
                                if call_id is not None:
                                    try:
                                        await ws_manager.store_call_ack(int(call_id))
                                    except (ValueError, TypeError):
                                        pass
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
        await ws_manager.mark_dm_offline(user_id)
        await release_ws_session(user_id)
