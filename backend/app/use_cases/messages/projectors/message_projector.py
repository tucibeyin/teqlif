import json
from app.core.events import DirectMessageCreatedEvent
from app.core.logger import get_logger

logger = get_logger(__name__)

# Bu mock bir Read Model'dir. Gerçekte bu Redis veya ClickHouse olacaktır.
# test_cqrs_read_models.py içerisinde sorgulamak için global bir dictionary kullanıyoruz.
READ_MODEL_CHAT_HISTORY = {}

async def project_message_created(event: DirectMessageCreatedEvent):
    """
    CQRS Projector (Yansıtıcı):
    PostgreSQL'e (Write Model) mesaj yazıldığında EventBus üzerinden bu fonsiyon tetiklenir.
    Görevi: Veriyi Read Model'e (ClickHouse/Redis/Memory) okumaya en uygun formata çevirerek kaydetmek.
    """
    logger.info("[MessageProjector] Event yakalandı: message_id=%s. Read Model güncelleniyor...", event.message_id)
    
    # Sohbet odası kimliği (küçük ID başa)
    room_id = f"{min(event.sender_id, event.receiver_id)}_{max(event.sender_id, event.receiver_id)}"
    
    if room_id not in READ_MODEL_CHAT_HISTORY:
        READ_MODEL_CHAT_HISTORY[room_id] = []
        
    # Sadece okuma arayüzüne (Frontend'e) gidecek kadar temiz ve düz (denormalize) veri
    read_data = {
        "id": event.message_id,
        "sender_id": event.sender_id,
        "content": event.content,
        "is_read": False
    }
    
    READ_MODEL_CHAT_HISTORY[room_id].append(read_data)
    
    logger.info("[MessageProjector] Read Model güncellendi | room_id=%s toplam_mesaj=%s", room_id, len(READ_MODEL_CHAT_HISTORY[room_id]))

def register_projectors():
    from app.core.event_bus import event_bus
    event_bus.subscribe(DirectMessageCreatedEvent, project_message_created)
    logger.info("[Projectors] MessageProjector EventBus'a kaydedildi.")
