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

@dataclass
class ListingCreatedEvent(DomainEvent):
    """CQRS: İlan oluşturulduğunda Projector'lara ve Notifier'lara haber verir."""
    listing_id: int
    user_id: int
    title: str
    category: str
    price: float | None
