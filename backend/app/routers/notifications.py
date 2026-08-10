from typing import List

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete, func
import asyncio

from app.models.enums import UserStatus
from app.database import get_db
from app.models.user import User
from app.models.notification import Notification
from app.schemas.notification import NotificationOut, UnreadCountOut
from app.utils.auth import get_current_user, decode_token
# push_notification servis katmanında — mevcut caller'lar için re-export
from app.services.notification_service import push_notification  # noqa: F401
from app.core.exceptions import NotFoundException
from app.core.logger import get_logger
from app.core.log_context import user_id_var
from app.core.task_queue import get_pool
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager

logger = get_logger(__name__)
router = APIRouter(prefix="/api/notifications", tags=["notifications"])



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
        raise NotFoundException(code="NOTIFICATION_NOT_FOUND")
    await db.delete(n)
    await db.commit()
    return {"ok": True}


@router.websocket("/ws")
async def notifications_ws(websocket: WebSocket):
    # ── 1. Bağlantıyı kabul et (token URL'de taşınmaz) ───────────────────────
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error("[NOTIF WS] accept() başarısız | %s", exc, exc_info=True)
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
        logger.warning("[NOTIF WS] Geçersiz token, bağlantı kapatıldı")
        await websocket.close(code=4001)
        return
    user_id_var.set(str(user_id))

    # ── 3. DB doğrulama ───────────────────────────────────────────────────────
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or user.status != UserStatus.ACTIVE:
                await websocket.close(code=4001)
                return
    except Exception as exc:
        logger.error("[NOTIF WS] DB doğrulama hatası | user_id=%s | %s", user_id, exc, exc_info=True)
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
            "[NOTIF WS] Eş zamanlı oturum limiti aşıldı | user_id=%s | count=%s limit=%s",
            user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    ws_manager.connect(websocket, f"notif:{user_id}")
    logger.info("[NOTIF WS] BAĞLANDI | user_id=%s", user_id)

    try:
        # Bağlantı kurulunca mevcut okunmamış sayısını gönder
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(func.count()).where(
                    Notification.user_id == user_id,
                    Notification.is_read == False,  # noqa: E712
                )
            )
            count = result.scalar_one()
        await websocket.send_json({"type": "unread_count", "count": count})

        # Keep-alive döngüsü
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
                if text.strip() == "ping":
                    await websocket.send_text("pong")
            except asyncio.TimeoutError:
                logger.warning("[NOTIF WS] İstemci ping timeout | user_id=%s", user_id)
                break
            except WebSocketDisconnect:
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.error("[NOTIF WS] HATA | user_id=%s | %s", user_id, exc)
    finally:
        ws_manager.disconnect(websocket, f"notif:{user_id}")
        await release_ws_session(user_id)
        logger.info("[NOTIF WS] AYRILDI | user_id=%s", user_id)
