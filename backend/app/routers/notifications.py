import logging
from datetime import datetime, timezone
from typing import Dict, Set, List

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete, func

from app.database import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.notification import Notification
from app.schemas.notification import NotificationOut, UnreadCountOut
from app.utils.auth import get_current_user, decode_token
from app.services.firebase_service import send_push

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/notifications", tags=["notifications"])

# In-memory WebSocket connections per user
_notif_connections: Dict[int, Set[WebSocket]] = {}


async def push_notification(user_id: int, notif: dict) -> None:
    """Save notification to DB and push to all active WS connections for the user."""
    async with AsyncSessionLocal() as db:
        n = Notification(
            user_id=user_id,
            type=notif.get("type", "info"),
            title=notif.get("title", ""),
            body=notif.get("body"),
            related_id=notif.get("related_id"),
        )
        db.add(n)
        await db.commit()
        await db.refresh(n)

    # FCM push (always, regardless of WS connection)
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user and user.fcm_token:
            # Count total unread notifications + messages for iOS badge
            unread_notifs = await db.scalar(
                select(func.count()).where(
                    Notification.user_id == user_id,
                    Notification.is_read == False,  # noqa: E712
                )
            ) or 0
            from app.models.message import DirectMessage
            unread_msgs = await db.scalar(
                select(func.count()).where(
                    DirectMessage.receiver_id == user_id,
                    DirectMessage.is_read == False,  # noqa: E712
                )
            ) or 0
            badge = unread_notifs + unread_msgs
            await send_push(user.fcm_token, notif.get("title", ""), notif.get("body"), badge=badge, notif_type=notif.get("type"))

    # Push to WS connections
    targets = list(_notif_connections.get(user_id, set()))
    if not targets:
        return
    dead = set()
    payload = {
        "type": "notification",
        "id": n.id,
        "notif_type": n.type,
        "title": n.title,
        "body": n.body,
        "related_id": n.related_id,
        "created_at": n.created_at.isoformat() if n.created_at else None,
    }
    for ws in targets:
        try:
            await ws.send_json(payload)
        except Exception as exc:
            logger.warning("[NOTIF WS] send error user_id=%s: %s", user_id, exc)
            dead.add(ws)
    for ws in dead:
        _notif_connections.get(user_id, set()).discard(ws)


@router.get("/", response_model=List[NotificationOut])
async def list_notifications(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Notification)
        .where(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
    )
    return result.scalars().all()


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(func.count()).where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,  # noqa: E712
            Notification.type != "message",  # DM'ler zaten ayrı sayılıyor
        )
    )
    count = result.scalar_one()
    return UnreadCountOut(count=count)


@router.post("/mark-all-read")
async def mark_all_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(Notification)
        .where(Notification.user_id == current_user.id, Notification.is_read == False)  # noqa: E712
        .values(is_read=True)
    )
    await db.commit()
    return {"ok": True}


@router.delete("/{notif_id}")
async def delete_notification(
    notif_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Notification).where(
            Notification.id == notif_id,
            Notification.user_id == current_user.id,
        )
    )
    n = result.scalar_one_or_none()
    if not n:
        raise HTTPException(status_code=404, detail="Bildirim bulunamadı")
    await db.delete(n)
    await db.commit()
    return {"ok": True}


@router.websocket("/ws")
async def notifications_ws(websocket: WebSocket, token: str = Query(...)):
    user_id = decode_token(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            await websocket.close(code=4001)
            return

    await websocket.accept()
    _notif_connections.setdefault(user_id, set()).add(websocket)
    logger.info("[NOTIF WS] BAĞLANDI | user_id=%s", user_id)

    try:
        # Send current unread count on connect
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(func.count()).where(
                    Notification.user_id == user_id,
                    Notification.is_read == False,  # noqa: E712
                )
            )
            count = result.scalar_one()
        await websocket.send_json({"type": "unread_count", "count": count})

        # Keep alive loop
        while True:
            try:
                text = await websocket.receive_text()
                if text.strip() == "ping":
                    await websocket.send_text("pong")
            except WebSocketDisconnect:
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[NOTIF WS] HATA | user_id=%s | %s", user_id, exc)
    finally:
        _notif_connections.get(user_id, set()).discard(websocket)
        logger.info("[NOTIF WS] AYRILDI | user_id=%s", user_id)
