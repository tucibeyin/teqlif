from app.core.logger import get_logger
from app.core.event_bus import event_bus
from app.core.events import StreamStartedEvent

logger = get_logger(__name__)


class StreamAnalyticsProjector:
    """Canlı yayın başladığında log kaydı tutar. stream:stats Redis key'i kaldırıldı (Faz 7.4)."""

    def __init__(self):
        event_bus.subscribe(StreamStartedEvent, self.handle_stream_started)

    async def handle_stream_started(self, event: StreamStartedEvent):
        logger.info("[StreamAnalyticsProjector] Stream started: %s (user: %s)", event.stream_id, event.user_id)


stream_projector = StreamAnalyticsProjector()
