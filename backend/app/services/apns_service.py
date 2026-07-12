import json
from aioapns import APNs, NotificationRequest, PushType
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

# Global APNs client instance
_apns_client = None

def get_apns_client() -> APNs | None:
    global _apns_client
    if _apns_client is not None:
        return _apns_client
    
    if not settings.apns_cert_path:
        logger.warning("[APNs] apns_cert_path is not set, VoIP pushes will be disabled.")
        return None
        
    try:
        _apns_client = APNs(
            client_cert=settings.apns_cert_path,
            use_sandbox=settings.apns_use_sandbox,
        )
        return _apns_client
    except Exception as e:
        logger.error(f"[APNs] Failed to initialize APNs client: {e}")
        return None

async def send_voip_push(token: str, payload: dict) -> bool:
    """
    Sends a VoIP push notification to the given VoIP token.
    VoIP pushes must have the .voip topic and usually carry a specific payload structure.
    """
    client = get_apns_client()
    if not client:
        return False

    try:
        topic = f"{settings.ios_bundle_id}.voip"
        
        request = NotificationRequest(
            device_token=token,
            message=payload,
            apns_topic=topic,
            push_type=PushType.VOIP
        )
        
        response = await client.send_notification(request)
        if response.is_successful:
            logger.info(f"[APNs] VoIP push sent successfully to {token[:10]}...")
            return True
        else:
            logger.error(f"[APNs] VoIP push failed: {response.description}")
            return False
    except Exception as e:
        logger.error(f"[APNs] Error sending VoIP push: {e}", exc_info=True)
        return False
