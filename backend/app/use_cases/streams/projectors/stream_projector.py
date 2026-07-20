from app.core.logger import get_logger
from app.core.event_bus import event_bus
from app.core.events import StreamStartedEvent

logger = get_logger(__name__)

class StreamAnalyticsProjector:
    """Canlı yayın başladığında stream istatistiklerini (Read Model) başlatır."""
    
    def __init__(self):
        self._subscribe()

    def _subscribe(self):
        event_bus.subscribe(StreamStartedEvent, self.handle_stream_started)
        logger.info("[StreamAnalyticsProjector] Subscribed to StreamStartedEvent")

    async def handle_stream_started(self, event: StreamStartedEvent):
        logger.info("[StreamAnalyticsProjector] Stream started: %s (user: %s)", event.stream_id, event.user_id)
        
        # Gerçekte Redis veya ClickHouse üzerinde Read Model oluşturulur
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        # Yayın istatistikleri (viewer_count, likes vb.) key'ini sıfırla
        await redis.hset(f"stream:stats:{event.stream_id}", mapping={"viewers": 0, "likes": 0, "status": "live"})
        
        logger.info("[StreamAnalyticsProjector] Read Model güncellendi (Redis)")

# Singleton Projector
stream_projector = StreamAnalyticsProjector()
