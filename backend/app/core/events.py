from dataclasses import dataclass
from app.core.event_bus import DomainEvent

@dataclass
class TokenInvalidatedEvent(DomainEvent):
    """FCM Token'ın geçersiz/silinmiş olduğu anlaşıldığında fırlatılır."""
    token: str

@dataclass
class DirectMessageCreatedEvent(DomainEvent):
    """CQRS: Yeni bir mesaj yazıldığında Read Modellerin güncellenmesi için fırlatılır."""
    message_id: int
    sender_id: int
    receiver_id: int
    content: str
