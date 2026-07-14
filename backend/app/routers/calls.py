"""
Voice call signaling endpoints.

Flow:
  POST /start        → caller gets LK token; callee gets WS event + FCM push
  POST /{id}/accept  → callee gets LK token; caller gets WS call_accepted
  POST /{id}/reject  → caller gets WS call_rejected
  POST /{id}/end     → other party gets WS call_ended; LK room deleted
  POST /{id}/missed  → callee gets WS call_missed (caller-side 30s timeout)
"""
import asyncio
import time
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_

from app.database import get_db, AsyncSessionLocal
from app.models.call import Call
from app.models.user import User
from app.models.notification import Notification
from app.utils.auth import get_current_user
from app.utils.i18n import _get_t, get_locale
from app.core.ws_manager import ws_manager
from app.core.logger import get_logger
from app.core.task_queue import get_pool
from app.config import settings
from app.core.exceptions import AppException
from app.services.apns_service import send_voip_push
from app.services.firebase_service import send_push

logger = get_logger(__name__)
router = APIRouter(prefix="/api/calls", tags=["calls"])

_DM_CHANNEL = "dm_broadcast"
_CALL_RING_TIMEOUT = 30  # seconds


def _make_livekit_token(room_name: str, user: User) -> str:
    from livekit.api import AccessToken, VideoGrants
    grant = VideoGrants(
        room_join=True,
        room=room_name,
        can_publish=True,
        can_subscribe=True,
        can_publish_data=True,
    )
    return (
        AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
        .with_identity(str(user.id))
        .with_name(user.username)
        .with_grants(grant)
        .to_jwt()
    )


async def _delete_lk_room(room_name: str) -> None:
    try:
        from livekit.api import LiveKitAPI, DeleteRoomRequest
        async with LiveKitAPI(
            url=settings.livekit_api_base,
            api_key=settings.livekit_api_key,
            api_secret=settings.livekit_api_secret,
        ) as api:
            await api.room.delete_room(DeleteRoomRequest(room=room_name))
    except Exception as exc:
        err_msg = str(exc).lower()
        if "not_found" in err_msg or "does not exist" in err_msg:
            logger.debug("[Calls] LK room silinirken atlandı (oda yok) | room=%s", room_name)
        else:
            logger.warning("[Calls] LK room silinemedi | room=%s | %s", room_name, exc)


@router.get("/{call_id}/status")
async def get_call_status(
    call_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = select(Call).where(Call.id == call_id)
    result = await db.execute(stmt)
    call = result.scalars().first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")

    return {
        "status": call.status,
        "accepted_at": call.accepted_at.isoformat() if call.accepted_at else None,
    }


async def _ws_broadcast(user_id: int, payload: dict) -> None:
    await ws_manager.publish(_DM_CHANNEL, f"dm:{user_id}", payload)


async def _send_call_push(
    callee: User,
    caller: User,
    call_id: int,
    room_name: str,
    callee_token: str,
    db: AsyncSession,
) -> None:
    """VoIP push (iOS) veya FCM fallback gönderir.

    Token yaş stratejisi (WhatsApp pattern):
      - Taze token  (<= 7 gün): sadece VoIP — batarya dostu, hızlı
      - Stale token (8-30 gün): VoIP + FCM aynı anda — biri mutlaka ulaşır
      - Çok eski    (> 30 gün): FCM önce, VoIP best-effort
    """
    if not callee.fcm_token and not callee.voip_token:
        return

    locale = get_locale(callee)
    t = _get_t(locale)

    title_raw = t.get("callNotifTitle", "@{username} sizi arıyor")
    body_raw = t.get("callNotifBody", "Gelen Sesli Arama")

    try:
        title = title_raw.format_map({"username": caller.username})
        body = body_raw.format_map({"username": caller.username})
    except (KeyError, ValueError):
        title = title_raw
        body = body_raw

    extra_data = {
        "call_id": str(call_id),
        "room_name": room_name,
        "caller_id": str(caller.id),
        "caller_username": caller.username,
        "caller_avatar": caller.profile_image_thumb_url or caller.profile_image_url or "",
        "livekit_url": settings.livekit_url,
        "callee_token": callee_token,
    }

    # Token yaşını hesapla
    token_age_days = 999
    if callee.voip_token and callee.voip_token_updated_at:
        delta = datetime.now(timezone.utc) - (
            callee.voip_token_updated_at
            if callee.voip_token_updated_at.tzinfo
            else callee.voip_token_updated_at.replace(tzinfo=timezone.utc)
        )
        token_age_days = delta.days

    async def _try_voip() -> bool:
        """VoIP push dener; başarısızsa token'ı temizler. True döner → başarılı."""
        if not callee.voip_token:
            return False
        logger.info(f"[Calls] VoIP push denemesi | user={callee.id} age={token_age_days}d")
        payload = {
            "aps": {"content-available": 1},
            **extra_data,
        }
        success, bad_token = await send_voip_push(callee.voip_token, payload)
        if bad_token:
            logger.warning(f"[Calls] VoIP token geçersiz, DB'den temizleniyor | user={callee.id}")
            callee.voip_token = None
            await db.commit()
        return success

    async def _try_fcm() -> None:
        """FCM push dener."""
        if not callee.fcm_token:
            return
        try:
            await send_push(
                token=callee.fcm_token,
                title=title,
                body=body,
                badge=None,
                notif_type="incoming_call",
                extra_data=extra_data,
            )
        except Exception as exc:
            logger.warning("[Calls] FCM push hatası: %s", exc)

    if callee.voip_token:
        if token_age_days <= 7:
            # TAZE: sadece VoIP — hızlı, batarya dostu
            logger.info(f"[Calls] Taze VoIP token ({token_age_days}gün) — sadece VoIP")
            ok = await _try_voip()
            if not ok:
                logger.info("[Calls] VoIP başarısız, FCM fallback")
                await _try_fcm()

        elif token_age_days <= 30:
            # STALE: VoIP + FCM eş zamanlı — biri mutlaka ulaşır
            logger.info(f"[Calls] Stale VoIP token ({token_age_days}gün) — VoIP + FCM eş zamanlı")
            await asyncio.gather(_try_voip(), _try_fcm())

        else:
            # ÇOK ESKİ: FCM önce, VoIP best-effort
            logger.info(f"[Calls] Çok eski VoIP token ({token_age_days}gün) — FCM önce")
            await asyncio.gather(_try_fcm(), _try_voip())
    else:
        # VoIP yok, sadece FCM
        await _try_fcm()


# ── POST /api/calls/start ─────────────────────────────────────────────────────

@router.post("/start")
async def start_call(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    callee_id: int = body.get("callee_id")
    if not callee_id or callee_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid callee_id")

    callee = await db.get(User, callee_id)
    if not callee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Check if caller is already in an active call
    caller_busy = await db.scalar(
        select(Call).where(
            or_(Call.caller_id == current_user.id, Call.callee_id == current_user.id),
            Call.status.in_(["calling", "active"])
        )
    )
    if caller_busy:
        raise AppException(status_code=409, message="Already in a call", code="CALLER_BUSY")

    # Check if callee is already in an active call
    active_call = await db.scalar(
        select(Call).where(
            or_(Call.caller_id == callee_id, Call.callee_id == callee_id),
            Call.status.in_(["calling", "active", "connecting", "connected"])
        )
    )
    if active_call:
        raise AppException(status_code=409, message="User is busy", code="USER_BUSY")

    room_name = f"call_{current_user.id}_{callee_id}_{int(time.time())}"
    call = Call(caller_id=current_user.id, callee_id=callee_id, room_name=room_name, status="calling")
    db.add(call)
    await db.commit()
    await db.refresh(call)

    token = _make_livekit_token(room_name, current_user)
    callee_token = _make_livekit_token(room_name, callee)

    # Notify callee via WS (foreground) + FCM (background)
    ws_payload = {
        "type": "call_incoming",
        "call_id": call.id,
        "room_name": room_name,
        "caller_id": current_user.id,
        "caller_username": current_user.username,
        "caller_avatar": current_user.profile_image_thumb_url or current_user.profile_image_url or "",
        "livekit_url": settings.livekit_url,
        "callee_token": callee_token,
    }
    await _ws_broadcast(callee_id, ws_payload)
    await _send_call_push(callee, current_user, call.id, room_name, callee_token, db)

    # Askıda kalan aramaları (Ghost calls) 35-40 sn sonra timeout'a çekmek için ARQ görevi ekle
    pool = get_pool()
    if pool:
        await pool.enqueue_job(
            "delayed_call_timeout_task",
            call.id,
            current_user.id,
            callee_id,
            _defer_by=timedelta(seconds=35),
            _job_id=f"call_timeout_{call.id}"
        )

    logger.info("[Calls] Arama başlatıldı | call_id=%d caller=%d callee=%d", call.id, current_user.id, callee_id)
    return {
        "call_id": call.id,
        "room_name": room_name,
        "livekit_url": settings.livekit_url,
        "token": token,
    }


# ── POST /api/calls/{id}/accept ───────────────────────────────────────────────

@router.post("/{call_id}/accept")
async def accept_call(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # SELECT FOR UPDATE — eş zamanlı iki accept isteği race condition'ı önler
    result = await db.execute(
        select(Call).where(Call.id == call_id).with_for_update()
    )
    call = result.scalar_one_or_none()
    if not call or call.callee_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")
    if call.status != "calling":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Call is no longer active")

    # accepted_at'ı yerel değişkene al — commit sonrası SQLAlchemy attribute expire olmaz
    accepted_at = datetime.now(timezone.utc)
    call.status = "active"
    call.accepted_at = accepted_at
    room_name = call.room_name
    caller_id = call.caller_id
    call_id_val = call.id
    await db.commit()

    token = _make_livekit_token(room_name, current_user)

    await _ws_broadcast(caller_id, {
        "type": "call_accepted",
        "call_id": call_id_val,
        "room_name": room_name,
        "accepted_at": accepted_at.isoformat(),
    })

    logger.info("[Calls] Arama kabul edildi | call_id=%d", call_id)
    return {
        "call_id": call_id_val,
        "room_name": room_name,
        "livekit_url": settings.livekit_url,
        "token": token,
        "accepted_at": accepted_at.isoformat(),
    }


# ── POST /api/calls/{id}/reject ───────────────────────────────────────────────

@router.post("/{call_id}/reject")
async def reject_call(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    call = await db.get(Call, call_id)
    if not call or call.callee_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")

    room_name = call.room_name
    caller_id = call.caller_id
    call_id_val = call.id
    call.status = "rejected"
    call.ended_at = datetime.now(timezone.utc)
    await db.commit()

    await _ws_broadcast(caller_id, {"type": "call_rejected", "call_id": call_id_val})
    caller = await db.get(User, caller_id)
    if caller and caller.fcm_token:
        logger.info(f"[Calls] Sending 'call_rejected' FCM push to {caller.username} (call_id={call_id})")
        await send_push(
            token=caller.fcm_token,
            title="",
            body="",
            notif_type="call_rejected",
            extra_data={"call_id": str(call_id_val)},
            is_silent=True
        )

    # LK room'u sil — reject sonrası oda askıda kalıyordu
    await _delete_lk_room(room_name)

    logger.info("[Calls] Arama reddedildi | call_id=%d", call_id)
    return {"ok": True}


# ── POST /api/calls/{id}/end ──────────────────────────────────────────────────

@router.post("/{call_id}/end")
async def end_call(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    call = await db.get(Call, call_id)
    if not call or current_user.id not in (call.caller_id, call.callee_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")

    # Idempotency: zaten bitmişse tekrar işleme, duplicate WS/FCM gönderme
    if call.status in ("ended", "rejected", "missed"):
        logger.debug("[Calls] /end called on already-terminal call | call_id=%d status=%s", call_id, call.status)
        return {"ok": True}

    # Yerel değişkenlere al — commit sonrası SQLAlchemy attribute expire olmaz
    other_id = call.callee_id if current_user.id == call.caller_id else call.caller_id
    call_id_val = call.id
    room_name = call.room_name
    accepted_at = call.accepted_at

    ended_at = datetime.now(timezone.utc)
    # Arama süresi hesapla (sadece bağlantı kurulmuş aramalarda)
    duration_seconds: int | None = None
    if accepted_at:
        acc = accepted_at if accepted_at.tzinfo else accepted_at.replace(tzinfo=timezone.utc)
        duration_seconds = max(0, int((ended_at - acc).total_seconds()))

    call.status = "ended"
    call.ended_at = ended_at
    call.duration_seconds = duration_seconds
    await db.commit()

    await _ws_broadcast(other_id, {"type": "call_ended", "call_id": call_id_val})
    other_user = await db.get(User, other_id)
    if other_user and other_user.fcm_token:
        logger.info(f"[Calls] Sending 'call_ended' FCM push to {other_user.username} from end_call endpoint (call_id={call_id})")
        try:
            await send_push(
                token=other_user.fcm_token,
                title="",
                body="",
                notif_type="call_ended",
                extra_data={"call_id": str(call_id_val)},
                is_silent=True
            )
        except Exception as push_err:
            logger.warning(f"[Calls] Failed to send 'call_ended' push: {push_err}")
    await _delete_lk_room(room_name)

    logger.info("[Calls] Arama bitti | call_id=%d duration=%s", call_id, duration_seconds)
    return {"ok": True}


# ── POST /api/calls/{id}/missed ───────────────────────────────────────────────

async def _send_missed_call_push(callee: User, caller: User) -> None:
    if not callee.fcm_token:
        return
    logger.info(f"[Calls] Sending 'call_missed' FCM push to {callee.username}")
    locale = get_locale(callee)
    t = _get_t(locale)

    title_raw = t.get("notifCallMissed", "Cevapsız Arama: @{username}")
    body_raw = t.get("notifCallMissedBody", "Size ulaşmaya çalıştı.")

    try:
        title = title_raw.format_map({"username": caller.username})
        body = body_raw.format_map({"username": caller.username})
    except (KeyError, ValueError):
        title = title_raw
        body = body_raw

    await send_push(
        token=callee.fcm_token,
        title=title,
        body=body,
        notif_type="call_missed",
        extra_data={"caller_username": caller.username, "related_id": str(caller.id)}
    )

@router.post("/{call_id}/missed")
async def missed_call(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    call = await db.get(Call, call_id)
    if not call or call.caller_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")

    if call.status == "calling":
        call.status = "missed"
        call.ended_at = datetime.now(timezone.utc)

        # Callee'yi bir kez çek — locale için ve push için aynı obje kullanılır
        callee = await db.get(User, call.callee_id)
        locale = get_locale(callee) if callee else get_locale(current_user)
        t = _get_t(locale)

        title_raw = t.get("notifCallMissed", "Cevapsız Arama: @{username}")
        body_raw = t.get("notifCallMissedBody", "Size ulaşmaya çalıştı.")

        try:
            title = title_raw.format_map({"username": current_user.username})
            body = body_raw.format_map({"username": current_user.username})
        except (KeyError, ValueError):
            title = title_raw
            body = body_raw

        n = Notification(
            user_id=call.callee_id,
            type="call_missed",
            title=title,
            body=body,
            related_id=current_user.id
        )
        db.add(n)

        await db.commit()
        await _ws_broadcast(call.callee_id, {"type": "call_missed", "call_id": call.id})
        await _delete_lk_room(call.room_name)

        if callee:
            # commit sonrası expire olan attribute'ları yenile
            await db.refresh(callee)
            await _send_missed_call_push(callee, current_user)

    logger.info("[Calls] Cevapsız arama | call_id=%d", call_id)
    return {"ok": True}
