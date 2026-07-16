import json
import time
from aioapns import APNs, NotificationRequest, PushType
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

# Global APNs client instance
_apns_client: APNs | None = None
_apns_last_failure: float = 0.0
_APNS_RETRY_COOLDOWN: int = 60  # seconds — failed init sonrası spam retry'ı önler

def get_apns_client() -> APNs | None:
    global _apns_client, _apns_last_failure

    if _apns_client is not None:
        return _apns_client
    
    if not settings.apns_cert_path:
        logger.warning("[APNs] apns_cert_path is not set, VoIP pushes will be disabled.")
        return None

    # Son başarısız init'ten bu yana cooldown süresi geçmediyse tekrar deneme
    if _apns_last_failure > 0 and (time.monotonic() - _apns_last_failure) < _APNS_RETRY_COOLDOWN:
        return None
        
    try:
        _apns_client = APNs(
            client_cert=settings.apns_cert_path,
            use_sandbox=settings.apns_use_sandbox,
        )
        logger.info("[APNs] Client initialized successfully.")
        return _apns_client
    except Exception as e:
        _apns_last_failure = time.monotonic()
        logger.error(f"[APNs] Failed to initialize APNs client: {e}")
        return None

async def send_voip_push(token: str, payload: dict) -> tuple[bool, bool]:
    """
    Sends a VoIP push notification to the given VoIP token.
    VoIP pushes must have the .voip topic and usually carry a specific payload structure.

    Returns:
        (success, bad_token): success=True if push delivered.
        bad_token=True if APNs says the token is invalid (BadDeviceToken / Unregistered /
        ExpiredToken) — caller should remove it from DB per Apple's guidelines.
    """
    client = get_apns_client()
    if not client:
        return False, False

    try:
        topic = f"{settings.ios_bundle_id}.voip"
        logger.info(
            "[CALL_PROCESS][APNS] send_voip_push | topic=%s sandbox=%s token=%s…",
            topic, settings.apns_use_sandbox, token[:10],
        )

        request = NotificationRequest(
            device_token=token,
            message=payload,
            apns_topic=topic,
            push_type=PushType.VOIP
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
