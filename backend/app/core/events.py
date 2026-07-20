from dataclasses import dataclass
from app.core.event_bus import DomainEvent

@dataclass
class TokenInvalidatedEvent(DomainEvent):
    """FCM Token'ın geçersiz/silinmiş olduğu anlaşıldığında fırlatılır."""
    token: str
