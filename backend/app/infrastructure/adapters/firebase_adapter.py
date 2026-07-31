import asyncio
from typing import Dict, Any

from app.core.ports.push_notification_port import PushNotificationPort
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import ServiceException
from app.core.circuit_breaker import fcm_breaker, CircuitOpenError

logger = get_logger(__name__)


class _FCMTokenError(Exception):
    """FCM token geçersiz veya kayıtsız — ARQ retry yapılmaz."""


class FirebaseAdapter(PushNotificationPort):
    """
    FCM V1 REST API'yi google-auth ile doğrudan çağıran Adapter.

    firebase_admin.messaging kullanmaz; AuthorizedSession token yönetimini
    tamamen üstlenir. di.py'de project_id ve sa_path ile initialize edilir.
    """

    FCM_SEND_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    def __init__(self, project_id: str | None, sa_path: str | None):
        self._project_id = project_id
        self._session = None
        if sa_path and project_id:
            try:
                from google.oauth2 import service_account
                import google.auth.transport.requests
                creds = service_account.Credentials.from_service_account_file(
                    sa_path,
                    scopes=["https://www.googleapis.com/auth/firebase.messaging"],
                )
                self._session = google.auth.transport.requests.AuthorizedSession(creds)
                logger.info(
                    "[FirebaseAdapter] FCM oturumu hazır | project=%s",
                    project_id,
                )
            except Exception as exc:
                logger.error(
                    "[FirebaseAdapter] FCM oturumu başlatılamadı: %s",
                    exc,
                    exc_info=True,
                )

    async def send_notification(
        self,
        token: str,
        title: str,
        body: str,
        data: Dict[str, Any] = None,
        is_silent: bool = False,
        ttl: int | None = None,
        android_channel_id: str | None = None,
    ) -> bool:
        if not token:
            logger.error("[FirebaseAdapter] send_notification çağrıldı ama token boş")
            return False

        if self._session is None:
            logger.error("[FirebaseAdapter] FCM oturumu yok — push devre dışı")
            return False

        try:
            async with fcm_breaker:
                msg = self._build_message(
                    token, title, body, data, is_silent, ttl, android_channel_id
                )
                message_id = await asyncio.to_thread(self._send_http, msg)
                logger.info(
                    "[FirebaseAdapter] Push başarılı | message_id=%s | token=%s…",
                    message_id,
                    token[:12],
                )
                return True

        except CircuitOpenError:
            logger.warning(
                "[FirebaseAdapter] Circuit AÇIK — push atlandı | token=%s…", token[:12]
            )
            return False
        except _FCMTokenError:
            logger.warning(
                "[FirebaseAdapter] Geçersiz/kayıtsız token (event fırlatılıyor) | token=%s…",
                token[:12],
            )
            from app.core.event_bus import event_bus
            from app.core.events import TokenInvalidatedEvent
            event_bus.publish(TokenInvalidatedEvent(token=token))
            return False
        except Exception as exc:
            logger.error(
                "[FirebaseAdapter] Push başarısız | token=%s… | hata=%s",
                token[:12],
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise ServiceException(f"Push notification failed: {exc}")

    def _build_message(
        self,
        token: str,
        title: str,
        body: str,
        data: Dict[str, Any] | None,
        is_silent: bool,
        ttl: int | None,
        android_channel_id: str | None,
    ) -> dict:
        formatted_data = {k: str(v) for k, v in data.items()} if data else {}

        msg: dict = {"token": token, "data": formatted_data}

        if not is_silent:
            msg["notification"] = {"title": title, "body": body}

        android: dict = {"priority": "high"}
        if ttl is not None:
            android["ttl"] = f"{ttl}s"
        if android_channel_id and not is_silent:
            android["notification"] = {"channel_id": android_channel_id}
        msg["android"] = android

        # iOS: apns-priority 10 olmadan arka planda/kapalıyken bildirim gösterilmez.
        # is_silent=True (VoIP) için yok — o akış apns_service.py'den PushType.VOIP ile gidiyor.
        if not is_silent:
            msg["apns"] = {
                "headers": {
                    "apns-priority": "10",
                    "apns-push-type": "alert",
                },
                "payload": {"aps": {"sound": "default"}},
            }

        return msg

    def _send_http(self, msg: dict) -> str:
        """FCM V1 REST API'ye senkron POST. asyncio.to_thread içinde çalışır."""
        url = self.FCM_SEND_URL.format(project_id=self._project_id)
        resp = self._session.post(url, json={"message": msg}, timeout=30)

        if resp.status_code == 200:
            return resp.json().get("name", "")

        # Hata kodunu parse et
        try:
            fcm_status = resp.json().get("error", {}).get("status", "")
        except Exception:
            fcm_status = ""

        logger.error(
            "[FirebaseAdapter] FCM HTTP hatası | status=%s | fcm_status=%s | token=%s…",
            resp.status_code,
            fcm_status,
            msg.get("token", "")[:12],
        )

        if resp.status_code in (400, 404):
            raise _FCMTokenError(
                f"Token geçersiz | http={resp.status_code} | fcm_status={fcm_status}"
            )

        resp.raise_for_status()
        return ""

    async def send_multicast(
        self, tokens: list[str], title: str, body: str, data: Dict[str, Any] = None
    ) -> dict:
        raise NotImplementedError("Multicast is not yet implemented")
