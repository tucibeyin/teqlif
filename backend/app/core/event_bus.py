import asyncio
import logging
from typing import Callable, Dict, List, Type

logger = logging.getLogger(__name__)

class DomainEvent:
    """Tüm domain olaylarının türeyeceği temel sınıf."""
    pass

class EventBus:
    """
    Uygulama içi asenkron Olay Yolu (Pub/Sub).
    
    Servislerin birbirini doğrudan import edip çağırmasını engeller.
    Bir servis bir olay fırlatır (publish), diğer servisler bu olaya abone olur (subscribe).
    """
    def __init__(self):
        self._handlers: Dict[Type[DomainEvent], List[Callable]] = {}

    def subscribe(self, event_type: Type[DomainEvent], handler: Callable):
        """Bir olay tipine asenkron veya senkron bir dinleyici kaydeder."""
        if event_type not in self._handlers:
            self._handlers[event_type] = []
        self._handlers[event_type].append(handler)
        logger.debug("[EventBus] Subscribed %s to %s", handler.__name__, event_type.__name__)

    def publish(self, event: DomainEvent):
        """
        Olayı (event) yayınlar ve ilgili tüm dinleyicileri (handlers)
        arka planda asenkron olarak tetikler (Fire and Forget).
        """
        handlers = self._handlers.get(type(event), [])
        if not handlers:
            logger.debug("[EventBus] No handlers for event %s", type(event).__name__)
            return
            
        for handler in handlers:
            asyncio.create_task(self._safe_invoke(handler, event))

    async def _safe_invoke(self, handler: Callable, event: DomainEvent):
        try:
            if asyncio.iscoroutinefunction(handler):
                await handler(event)
            else:
                handler(event)
        except Exception as exc:
            logger.exception(
                "[EventBus] Error handling event %s in %s: %s", 
                type(event).__name__, 
                handler.__name__, 
                exc
            )

# Global EventBus nesnesi
event_bus = EventBus()
