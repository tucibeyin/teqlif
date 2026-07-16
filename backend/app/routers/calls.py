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


@router.get("/{call_id}/callee-token")
async def get_callee_token(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    VoIP push token'ı taşımaz — callee, uyanınca bu endpoint'ten taze LK token'ını çeker.
    Sadece call.callee_id == current_user.id ise erişilebilir.
    """
    call = await db.get(Call, call_id)
    if not call or call.callee_id != current_user.id:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status not in ("calling", "active"):
        logger.warning(
            "[CALL_PROCESS][IN] callee-token rejected — call not active | call_id=%d status=%s",
            call_id, call.status,
        )
        raise HTTPException(status_code=409, detail="Call not active")

    token = _make_livekit_token(call.room_name, current_user)
    logger.info(
        "[CALL_PROCESS][IN] callee-token issued | call_id=%d callee=%d room=%s",
        call_id, current_user.id, call.room_name,
    )
    return {
        "token": token,
        "livekit_url": settings.livekit_url,
        "room_name": call.room_name,
    }


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
    logger.info(
        "[CALL_PROCESS][PUSH] _send_call_push | callee=%d voip=%s fcm=%s",
        callee.id,
        f"{callee.voip_token[:10]}…" if callee.voip_token else "NONE",
        f"{callee.fcm_token[:10]}…" if callee.fcm_token else "NONE",
    )
    if not callee.fcm_token and not callee.voip_token:
        logger.warning("[CALL_PROCESS][PUSH] callee=%d has NO push tokens — push skipped", callee.id)
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

    # FCM payload: tam veri — Android flutter_callkit_incoming extra dict'i doğru map eder
    fcm_extra_data = {
        "call_id": str(call_id),
        "room_name": room_name,
        "caller_id": str(caller.id),
        "caller_username": caller.username,
        "caller_avatar": caller.profile_image_thumb_url or caller.profile_image_url or "",
        "livekit_url": settings.livekit_url,
        "callee_token": callee_token,
    }

    # VoIP (APNs) payload: minimal — JWT token push payload'ında olmamalı.
    # iOS callee uyanınca GET /calls/:id/callee-token ile taze token çeker.
    # flutter_callkit_incoming native handler'ı sadece bilinen alanları map eder;
    # custom alanlar ancak "extra" alt dict'inde ulaşılabilir olur.
    voip_extra_data = {
        "call_id": str(call_id),
        "room_name": room_name,
        "caller_id": str(caller.id),
        "caller_username": caller.username,
        "caller_avatar": caller.profile_image_thumb_url or caller.profile_image_url or "",
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
        logger.info(
            "[CALL_PROCESS][PUSH] VoIP push attempt | callee=%d tokenAge=%dd token=%s…",
            callee.id, token_age_days, callee.voip_token[:10],
        )
        # VoIP payload'ında JWT yok — callee API'den çeker (GET /callee-token)
        payload = {
            "aps": {"content-available": 1},
            **voip_extra_data,
        }
        success, bad_token = await send_voip_push(callee.voip_token, payload)
        logger.info(
            "[CALL_PROCESS][PUSH] VoIP push result | callee=%d success=%s bad_token=%s",
            callee.id, success, bad_token,
        )
        if bad_token:
            logger.warning("[CALL_PROCESS][PUSH] VoIP token invalid → clearing from DB | callee=%d", callee.id)
            callee.voip_token = None
            await db.commit()
        return success

    async def _try_fcm() -> None:
        """FCM push dener."""
        if not callee.fcm_token:
            logger.warning("[CALL_PROCESS][PUSH] FCM push skipped — no fcm_token | callee=%d", callee.id)
            return
        logger.info("[CALL_PROCESS][PUSH] FCM push attempt | callee=%d token=%s…", callee.id, callee.fcm_token[:10])
        try:
            await send_push(
                token=callee.fcm_token,
                title=title,
                body=body,
                badge=None,
                notif_type="incoming_call",
                extra_data=fcm_extra_data,  # FCM: full payload with callee_token
            )
            logger.info("[CALL_PROCESS][PUSH] FCM push sent | callee=%d", callee.id)
        except Exception as exc:
            logger.warning("[CALL_PROCESS][PUSH] FCM push FAILED | callee=%d | %s", callee.id, exc)

    if callee.voip_token:
        if token_age_days <= 7:
            logger.info("[CALL_PROCESS][PUSH] strategy=VoIP_ONLY | tokenAge=%dd", token_age_days)
            ok = await _try_voip()
            if not ok:
                logger.info("[CALL_PROCESS][PUSH] VoIP failed → FCM fallback | callee=%d", callee.id)
                await _try_fcm()

        elif token_age_days <= 30:
            logger.info("[CALL_PROCESS][PUSH] strategy=VoIP+FCM_PARALLEL | tokenAge=%dd", token_age_days)
            await asyncio.gather(_try_voip(), _try_fcm())

        else:
            logger.info("[CALL_PROCESS][PUSH] strategy=FCM_FIRST+VoIP_BESTEFFORT | tokenAge=%dd", token_age_days)
            await asyncio.gather(_try_fcm(), _try_voip())
    else:
        logger.info("[CALL_PROCESS][PUSH] strategy=FCM_ONLY (no voip_token) | callee=%d", callee.id)
        await _try_fcm()


# ── POST /api/calls/start ─────────────────────────────────────────────────────

@router.post("/start")
async def start_call(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    callee_id: int = body.get("callee_id")
    logger.info("[CALL_PROCESS][OUT] start_call ENTER | caller=%d callee_id=%s", current_user.id, callee_id)
    if not callee_id or callee_id == current_user.id:
        logger.warning("[CALL_PROCESS][OUT] start_call REJECTED | reason=invalid_callee_id caller=%d callee_id=%s", current_user.id, callee_id)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid callee_id")

    callee = await db.get(User, callee_id)
    if not callee:
        logger.warning("[CALL_PROCESS][OUT] start_call REJECTED | reason=callee_not_found caller=%d callee_id=%d", current_user.id, callee_id)
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Check if caller is already in an active call
    caller_busy = await db.scalar(
        select(Call).where(
            or_(Call.caller_id == current_user.id, Call.callee_id == current_user.id),
            Call.status.in_(["calling", "active"])
        )
    )
    if caller_busy:
        logger.warning("[CALL_PROCESS][OUT] start_call REJECTED | reason=CALLER_BUSY caller=%d busy_call_id=%s", current_user.id, caller_busy)
        raise AppException(status_code=409, message="Already in a call", code="CALLER_BUSY")

    # Check if callee is already in an active call
    active_call = await db.scalar(
        select(Call).where(
            or_(Call.caller_id == callee_id, Call.callee_id == callee_id),
            Call.status.in_(["calling", "active", "connecting", "connected"])
        )
    )
    if active_call:
        logger.warning("[CALL_PROCESS][OUT] start_call REJECTED | reason=USER_BUSY caller=%d callee=%d", current_user.id, callee_id)
        raise AppException(status_code=409, message="User is busy", code="USER_BUSY")

    room_name = f"call_{current_user.id}_{callee_id}_{int(time.time())}"
    call = Call(caller_id=current_user.id, callee_id=callee_id, room_name=room_name, status="calling")
    db.add(call)
    await db.commit()
    await db.refresh(call)
    logger.info("[CALL_PROCESS][OUT] start_call: DB call created | call_id=%d room=%s", call.id, room_name)

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

    logger.info(
        "[CALL_PROCESS][OUT] start_call: WS+Push sent | call_id=%d callee=%d callee_voip=%s callee_fcm=%s",
        call.id, callee_id,
        "YES" if callee.voip_token else "NO",
        "YES" if callee.fcm_token else "NO",
    )
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
        logger.info("[CALL_PROCESS][OUT] start_call: ARQ timeout task enqueued | call_id=%d defer=35s", call.id)
    else:
        logger.warning("[CALL_PROCESS][OUT] start_call: ARQ pool not available — timeout task NOT enqueued | call_id=%d", call.id)

    logger.info(
        "[CALL_PROCESS][OUT] start_call OK | call_id=%d caller=%d callee=%d room=%s callee_voip=%s callee_fcm=%s",
        call.id, current_user.id, callee_id, room_name,
        "YES" if callee.voip_token else "NO",
        "YES" if callee.fcm_token else "NO",
    )
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
    logger.info("[CALL_PROCESS][IN] accept_call ENTER | call_id=%d callee=%d", call_id, current_user.id)
    # SELECT FOR UPDATE — eş zamanlı iki accept isteği race condition'ı önler
    result = await db.execute(
        select(Call).where(Call.id == call_id).with_for_update()
    )
    call = result.scalar_one_or_none()
    if not call or call.callee_id != current_user.id:
        logger.warning("[CALL_PROCESS][IN] accept_call NOT FOUND | call_id=%d callee=%d", call_id, current_user.id)
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")
    if call.status != "calling":
        logger.warning("[CALL_PROCESS][IN] accept_call CONFLICT | call_id=%d current_status=%s", call_id, call.status)
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

    logger.info(
        "[CALL_PROCESS][IN] accept_call OK | call_id=%d callee=%d caller=%d accepted_at=%s",
        call_id, current_user.id, caller_id, accepted_at.isoformat(),
    )
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
    logger.info("[CALL_PROCESS][IN] reject_call ENTER | call_id=%d callee=%d", call_id, current_user.id)
    call = await db.get(Call, call_id)
    if not call or call.callee_id != current_user.id:
        logger.warning("[CALL_PROCESS][IN] reject_call NOT FOUND | call_id=%d callee=%d", call_id, current_user.id)
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

    logger.info(
        "[CALL_PROCESS][IN] reject_call OK | call_id=%d callee=%d caller=%d room=%s",
        call_id, current_user.id, caller_id, room_name
    )
    return {"ok": True}


# ── POST /api/calls/{id}/end ──────────────────────────────────────────────────

@router.post("/{call_id}/end")
async def end_call(
    call_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    logger.info("[CALL_PROCESS][END] end_call ENTER | call_id=%d by=%d", call_id, current_user.id)
    call = await db.get(Call, call_id)
    if not call or current_user.id not in (call.caller_id, call.callee_id):
        logger.warning("[CALL_PROCESS][END] end_call NOT FOUND | call_id=%d by=%d", call_id, current_user.id)
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Call not found")

    # Idempotency: zaten bitmişse tekrar işleme, duplicate WS/FCM gönderme
    if call.status in ("ended", "rejected", "missed"):
        logger.info("[CALL_PROCESS][END] end_call ALREADY TERMINAL | call_id=%d status=%s by=%d", call_id, call.status, current_user.id)
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

    logger.info(
        "[CALL_PROCESS][END] end_call OK | call_id=%d by=%d duration=%ss",
        call_id, current_user.id, duration_seconds,
    )
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
    logger.info("[CALL_PROCESS][END] missed_call ENTER | call_id=%d caller=%d", call_id, current_user.id)
    call = await db.get(Call, call_id)
    if not call or call.caller_id != current_user.id:
        logger.warning("[CALL_PROCESS][END] missed_call NOT FOUND | call_id=%d caller=%d", call_id, current_user.id)
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

    logger.info("[CALL_PROCESS][END] missed_call OK | call_id=%d caller=%d", call_id, current_user.id)
    return {"ok": True}
