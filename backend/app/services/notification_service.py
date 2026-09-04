"""
Bildirim servisi — push notification iş mantığını router'dan ayırır.

push_notification(): Kalıcı bildirimler (follow, bid, vb.)
  - Kullanıcı bildirim tercihlerini kontrol eder
  - ARB anahtarlarını alıcı locale'ine göre çevirir
  - Bildirimi DB'ye kaydeder
  - FCM push'u ARQ kuyruğuna alır (veya direkt gönderir)
  - WebSocket bağlantılarına fan-out yapar

send_message_push(): DM-özel push
  - WS bağlıysa gönderme (DM zaten WS üzerinden iletiliyor)
  - DB'ye Notification kaydı yazmaz
  - Yalnızca messages pref'ini kontrol eder
"""
from datetime import datetime, timezone, timedelta

from sqlalchemy import select, func

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.notification import Notification
from app.models.message import DirectMessage
from app.core.task_queue import get_pool
from app.core.logger import get_logger
from app.core.ws_manager import ws_manager
from app.services.firebase_service import send_push

logger = get_logger(__name__)


def _in_quiet_window(from_str: str, to_str: str) -> bool:
    """Şu anki İstanbul saatinin sessiz saat aralığında olup olmadığını kontrol eder."""
    try:
        istanbul = timezone(timedelta(hours=3))
        now = datetime.now(istanbul)
        cur = now.hour * 60 + now.minute
        fh, fm = map(int, from_str.split(":"))
        th, tm = map(int, to_str.split(":"))
        f = fh * 60 + fm
        t = th * 60 + tm
        if f < t:
            return f <= cur < t
        return cur >= f or cur < t  # gece yarısını aşan aralık (ör. 22:00–08:00)
    except (ValueError, AttributeError):
        return False


async def push_notification(
    user_id: int,
    notif: dict,
    pref_key: str | None = None,
    amount: float | None = None,
) -> None:
    """Save notification to DB and push to all active WS connections for the user."""
    from app.schemas.user import DEFAULT_NOTIF_PREFS
    from app.utils.i18n import _get_t

    notif_type = notif.get("type", "?")
    logger.info("[PUSH] push_notification çağrıldı | user_id=%s | type=%s | pref_key=%s", user_id, notif_type, pref_key)

    suppress_push = False  # True → DB'ye yaz ama FCM/WS gönderme
    user_locale = "tr"

    # Single DB query covers both pref check and locale resolution
    if pref_key or "i18n" in notif:
        async with AsyncSessionLocal() as db:
            user = await db.get(User, user_id)
            if user:
                user_locale = user.locale or "tr"
                if pref_key:
                    prefs = user.notification_prefs or {}
                    merged = {**DEFAULT_NOTIF_PREFS, **prefs}
                    if not merged.get(pref_key, True):
                        return
                    # Teklif eşiği: eşik altındaysa bildirimi tamamen atla (DB'ye de yazma)
                    if pref_key == "new_bid" and amount is not None:
                        threshold = int(merged.get("bid_threshold_tl", 0))
                        if threshold > 0 and amount < threshold:
                            return
                    # Sessiz saatler: FCM push'u bastır, DB'ye yaz
                    if merged.get("quiet_hours_enabled", False):
                        if _in_quiet_window(
                            str(merged.get("quiet_from", "22:00")),
                            str(merged.get("quiet_to", "08:00")),
                        ):
                            suppress_push = True

    # i18n: translate title/body from ARB keys using recipient's locale
    i18n = notif.get("i18n")
    if i18n:
        t = _get_t(user_locale)
        notif = {k: v for k, v in notif.items() if k != "i18n"}  # strip meta

        def _fmt(key: str, params: dict) -> str:
            raw = t.get(key, "")
            if not raw:
                return ""
            # Resolve cat_* param values to localized category labels
            resolved = {
                k: t.get(v, v) if isinstance(v, str) and v.startswith("cat_") else v
                for k, v in params.items()
            }
            try:
                return raw.format_map(resolved)
            except (KeyError, ValueError):
                return raw

        title_key = i18n.get("title_key")
        body_key  = i18n.get("body_key")
        if title_key:
            notif["title"] = _fmt(title_key, i18n.get("title_params") or {})
        if body_key:
            notif["body"] = _fmt(body_key, i18n.get("body_params") or {})

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

    if suppress_push:
        logger.info("[PUSH] Sessiz saat — push bastırıldı | user_id=%s", user_id)
        return

    # FCM push (always, regardless of WS connection)
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user is None:
            logger.warning("[PUSH] Kullanıcı bulunamadı | user_id=%s", user_id)
            return
        has_token = bool(user.fcm_token)
        logger.info("[PUSH] FCM token kontrol | user_id=%s | token=%s", user_id, f"{user.fcm_token[:20]}…" if has_token else "YOK")
        if user and user.fcm_token:
            logger.info("[PUSH] FCM kuyruğa alınıyor | user_id=%s | token=%s… | type=%s", user_id, user.fcm_token[:12], notif_type)
            # Count total unread notifications + messages for iOS badge
            unread_notifs = await db.scalar(
                select(func.count()).where(
                    Notification.user_id == user_id,
                    Notification.is_read == False,  # noqa: E712
                    Notification.type != "message",  # DM'ler zaten ayrı sayılıyor
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

            # Ek data payload: deep link için gerekli tüm alanlar
            extra_data: dict[str, str] = {}
            if notif.get("related_id") is not None:
                extra_data["sender_id"] = str(notif["related_id"])
            if notif.get("sender_username"):
                extra_data["sender_username"] = str(notif["sender_username"])
            if notif.get("stream_id") is not None:
                extra_data["stream_id"] = str(notif["stream_id"])
            if notif.get("listing_id") is not None:
                extra_data["listing_id"] = str(notif["listing_id"])

            image_url: str | None = notif.get("sender_image_url")
            if image_url and not image_url.startswith("http"):
                image_url = f"https://www.teqlif.com{image_url}"

            # FCM push kuyruğa alınır — push_notification bloklanmaz
            pool = get_pool()
            if pool:
                job = await pool.enqueue_job(
                    "send_push_notification_task",
                    user.fcm_token,
                    notif.get("title", ""),
                    notif.get("body"),
                    badge,
                    notif.get("type"),
                    extra_data or None,
                    image_url,
                    _queue_name="critical",
                )
                logger.info("[PUSH] ARQ kuyruğuna alındı | job_id=%s | user_id=%s", getattr(job, 'job_id', '?'), user_id)
            else:
                # Worker başlatılmamışsa (geliştirme ortamı) direkt gönder
                logger.warning("[PUSH] ARQ pool yok — direkt gönderiliyor | user_id=%s", user_id)
                try:
                    await send_push(
                        user.fcm_token, notif.get("title", ""), notif.get("body"),
                        badge=badge, notif_type=notif.get("type"),
                        extra_data=extra_data or None, image_url=image_url,
                    )
                except Exception as exc:
                    from app.services.firebase_service import InvalidFCMTokenError
                    if isinstance(exc, InvalidFCMTokenError):
                        logger.warning("[PUSH] Geçersiz token EventBus tarafından temizlenecek | user_id=%s", user_id)
                    else:
                        raise

    # Push to WS connections — GlobalWSManager ile paralel fan-out
    notif_payload = {
        "type": "notification",
        "id": n.id,
        "notif_type": n.type,
        "title": n.title,
        "body": n.body,
        "related_id": n.related_id,
        "created_at": n.created_at.isoformat() if n.created_at else None,
    }
    await ws_manager.broadcast_local(f"notif:{user_id}", notif_payload)


async def send_message_push(user_id: int, notif: dict) -> None:
    """
    DM-özel push: WS bağlıysa gönderme, DB'ye Notification kaydı yazmaz.

    push_notification()'dan farkı:
    - is_dm_online kontrolü — bağlıysa WS zaten teslim ediyor, FCM gereksiz
    - notifications tablosuna kayıt yazmaz (DM'ler direct_messages'ta tutuluyor)
    - Yalnızca "messages" bildirim tercihini kontrol eder
    """
    from app.schemas.user import DEFAULT_NOTIF_PREFS
    from app.utils.i18n import _get_t

    # 1. DM WS bağlıysa push gereksiz
    if await ws_manager.is_dm_online(user_id):
        logger.debug("[MSG_PUSH] DM WS aktif — push atlandı | user_id=%s", user_id)
        return

    async with AsyncSessionLocal() as db:
        user = await db.get(User, user_id)
        if not user or not user.fcm_token:
            return

        # 2. messages bildirim tercihi kontrolü
        prefs = user.notification_prefs or {}
        merged = {**DEFAULT_NOTIF_PREFS, **prefs}
        if not merged.get("messages", True):
            logger.debug("[MSG_PUSH] messages bildirimleri kapalı | user_id=%s", user_id)
            return

        # 3. i18n çözümle
        user_locale = user.locale or "tr"
        i18n = notif.get("i18n")
        resolved: dict = {k: v for k, v in notif.items() if k != "i18n"}
        if i18n:
            t = _get_t(user_locale)

            def _fmt(key: str, params: dict) -> str:
                raw = t.get(key, "")
                try:
                    return raw.format_map(params) if raw else ""
                except (KeyError, ValueError):
                    return raw

            title_key = i18n.get("title_key")
            body_key = i18n.get("body_key")
            if title_key:
                resolved["title"] = _fmt(title_key, i18n.get("title_params") or {})
            if body_key:
                resolved["body"] = _fmt(body_key, i18n.get("body_params") or {})

        # 4. Badge hesapla (unread notifs + unread DM'ler)
        unread_notifs = await db.scalar(
            select(func.count()).where(
                Notification.user_id == user_id,
                Notification.is_read == False,  # noqa: E712
                Notification.type != "message",
            )
        ) or 0
        unread_msgs = await db.scalar(
            select(func.count()).where(
                DirectMessage.receiver_id == user_id,
                DirectMessage.is_read == False,  # noqa: E712
            )
        ) or 0
        badge = unread_notifs + unread_msgs

    # 5. FCM gönder (kuyruğa veya direkt) — DB işlemi kapandıktan sonra
    notif_type = resolved.get("type", "message")
    extra_data: dict[str, str] = {}
    if resolved.get("related_id") is not None:
        extra_data["sender_id"] = str(resolved["related_id"])
    if resolved.get("sender_username"):
        extra_data["sender_username"] = str(resolved["sender_username"])

    pool = get_pool()
    if pool:
        job = await pool.enqueue_job(
            "send_push_notification_task",
            user.fcm_token,
            resolved.get("title", ""),
            resolved.get("body"),
            badge,
            notif_type,
            extra_data or None,
            None,  # image_url — DM push'unda kullanılmaz
            _queue_name="critical",
        )
        logger.info("[MSG_PUSH] ARQ kuyruğuna alındı | job_id=%s | user_id=%s", getattr(job, "job_id", "?"), user_id)
    else:
        logger.warning("[MSG_PUSH] ARQ pool yok — direkt gönderiliyor | user_id=%s", user_id)
        try:
            await send_push(
                user.fcm_token,
                resolved.get("title", ""),
                resolved.get("body"),
                badge=badge,
                notif_type=notif_type,
                extra_data=extra_data or None,
                image_url=None,
            )
        except Exception as exc:
            from app.services.firebase_service import InvalidFCMTokenError
            if isinstance(exc, InvalidFCMTokenError):
                logger.warning("[MSG_PUSH] Geçersiz FCM token | user_id=%s", user_id)
            else:
                raise
