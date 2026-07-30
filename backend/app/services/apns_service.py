import time
from aioapns import APNs, NotificationRequest, PushType
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

_apns_client: APNs | None = None
_apns_last_failure: float = 0.0
_APNS_RETRY_COOLDOWN: int = 60  # failed init sonrası spam retry'ı önler


def _use_token_auth() -> bool:
    """Token-based auth için gerekli üç alan da doldurulmuşsa True."""
    return bool(settings.apns_key_path and settings.apns_key_id and settings.apns_team_id)


def get_apns_client() -> APNs | None:
    global _apns_client, _apns_last_failure

    if _apns_client is not None:
        return _apns_client

    if _apns_last_failure > 0 and (time.monotonic() - _apns_last_failure) < _APNS_RETRY_COOLDOWN:
        return None

    try:
        if _use_token_auth():
            # Token-based auth (.p8) — süresi dolmaz, tercih edilen yöntem.
            _apns_client = APNs(
                key=settings.apns_key_path,
                key_id=settings.apns_key_id,
                team_id=settings.apns_team_id,
                use_sandbox=settings.apns_use_sandbox,
            )
            logger.info("[APNs] Client initialized (token-based / .p8).")
        elif settings.apns_cert_path:
            # Sertifika bazlı auth (.pem) — yıllık yenileme gerekir, fallback.
            _apns_client = APNs(
                client_cert=settings.apns_cert_path,
                use_sandbox=settings.apns_use_sandbox,
            )
            logger.warning(
                "[APNs] Client initialized (cert-based / .pem) — "
                "sertifika yıllık yenilenmeli. Token-based (.p8) geçişi önerilir."
            )
        else:
            logger.warning("[APNs] Ne apns_key_path ne de apns_cert_path ayarlı — VoIP push devre dışı.")
            return None

        return _apns_client
    except Exception as e:
        _apns_last_failure = time.monotonic()
        logger.error("[APNs] Client init başarısız: %s", e)
        return None


async def send_voip_push(token: str, payload: dict) -> tuple[bool, bool]:
    """
    VoIP push gönderir.

    Returns:
        (success, bad_token): success=True → push iletildi.
        bad_token=True → APNs token'ı geçersiz dedi; DB'den silinmeli.
    """
    client = get_apns_client()
    if not client:
        return False, False

    try:
        topic = f"{settings.ios_bundle_id}.voip"
        auth_method = "token" if _use_token_auth() else "cert"
        logger.info(
            "[CALL_PROCESS][APNS] send_voip_push | topic=%s auth=%s sandbox=%s token=%s…",
            topic, auth_method, settings.apns_use_sandbox, token[:10],
        )

        request = NotificationRequest(
            device_token=token,
            message=payload,
            apns_topic=topic,
            push_type=PushType.VOIP,
        )

        response = await client.send_notification(request)
        if response.is_successful:
            logger.info("[CALL_PROCESS][APNS] VoIP push SUCCESS | topic=%s token=%s…", topic, token[:10])
            return True, False
        else:
            is_bad_token = response.description in ("BadDeviceToken", "Unregistered", "ExpiredToken")
            logger.error(
                "[CALL_PROCESS][APNS] VoIP push FAILED | topic=%s description=%s bad_token=%s",
                topic, response.description, is_bad_token,
            )
            return False, is_bad_token
    except Exception as e:
        logger.error("[CALL_PROCESS][APNS] VoIP push EXCEPTION | %s", e, exc_info=True)
        return False, False
