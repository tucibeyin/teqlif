"""Pre-flight politika kontrolleri — arama başlatılmadan önce çalışır."""
from app.core.exceptions import AppException
from app.core.logger import get_logger

logger = get_logger(__name__)


class CallPolicy:
    """Arama başlatılabilirliğini tek noktada kontrol eder.

    Yeni kural eklemek için bu sınıfa metod ekle — router'a if/else koyma.
    """

    async def check_callee_callable(self, callee) -> None:
        """Callee'nin şu an aranamayacağı durumları AppException ile işaretler."""
        from app.services.call_presence import is_live_streaming

        if await is_live_streaming(callee.id):
            prefs = callee.notification_prefs or {}
            block = prefs.get("block_calls_while_live", True)
            logger.info(
                "[CALL_POLICY] callee=%d is live_streaming | block_calls_while_live=%s",
                callee.id, block,
            )
            if block:
                raise AppException(
                    status_code=409,
                    message="User is live streaming",
                    code="USER_LIVE_BUSY",
                )
