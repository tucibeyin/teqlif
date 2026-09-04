import time
from aioapns import APNs, NotificationRequest, PushType
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

# Per-sandbox client cache: {sandbox: APNs | None}
_apns_clients: dict[bool, APNs | None] = {True: None, False: None}
_apns_last_failures: dict[bool, float] = {True: 0.0, False: 0.0}
_APNS_RETRY_COOLDOWN: int = 60


def _use_token_auth() -> bool:
    """Token-based auth için gerekli üç alan da doldurulmuşsa True."""
    return bool(settings.apns_key_path and settings.apns_key_id and settings.apns_team_id)


def get_apns_client(sandbox: bool) -> APNs | None:
    global _apns_clients, _apns_last_failures

    if _apns_clients[sandbox] is not None:
        return _apns_clients[sandbox]

    last_failure = _apns_last_failures[sandbox]
    if last_failure > 0 and (time.monotonic() - last_failure) < _APNS_RETRY_COOLDOWN:
        return None

    try:
        if _use_token_auth():
            _apns_clients[sandbox] = APNs(
                key=settings.apns_key_path,
                key_id=settings.apns_key_id,
                team_id=settings.apns_team_id,
                topic=f"{settings.ios_bundle_id}.voip",
                use_sandbox=sandbox,
            )
            logger.info("[APNs] Client initialized (token-based / .p8) sandbox=%s.", sandbox)
        elif settings.apns_cert_path:
            _apns_clients[sandbox] = APNs(
                client_cert=settings.apns_cert_path,
                use_sandbox=sandbox,
            )
            logger.warning(
                "[APNs] Client initialized (cert-based / .pem) sandbox=%s — "
                "sertifika yıllık yenilenmeli. Token-based (.p8) geçişi önerilir.", sandbox
            )
        else:
            logger.warning("[APNs] Ne apns_key_path ne de apns_cert_path ayarlı — VoIP push devre dışı.")
            return None

        return _apns_clients[sandbox]
    except Exception as e:
        _apns_last_failures[sandbox] = time.monotonic()
        logger.error("[APNs] Client init başarısız sandbox=%s: %s", sandbox, e)
        return None


async def send_voip_push(
    token: str,
    payload: dict,
    sandbox: bool | None = None,
) -> tuple[bool, bool]:
    """
    VoIP push gönderir.

    sandbox: Per-token APNs ortamı. None ise settings.apns_use_sandbox'a fallback.

    Returns:
        (success, bad_token): success=True → push iletildi.
        bad_token=True → APNs token'ı geçersiz dedi; DB'den silinmeli.
    """
    effective_sandbox = sandbox if sandbox is not None else settings.apns_use_sandbox
    client = get_apns_client(effective_sandbox)
    if not client:
        return False, False

    try:
        topic = f"{settings.ios_bundle_id}.voip"
        auth_method = "token" if _use_token_auth() else "cert"
        logger.info(
            "[CALL_PROCESS][APNS] send_voip_push | topic=%s auth=%s sandbox=%s token=%s…",
            topic, auth_method, effective_sandbox, token[:10],
        )

        request = NotificationRequest(
            device_token=token,
            message=payload,
            apns_topic=topic,
            push_type=PushType.VOIP,
            time_to_live=45,
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
