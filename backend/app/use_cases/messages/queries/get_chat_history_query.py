from app.core.logger import get_logger
from app.use_cases.messages.projectors.message_projector import READ_MODEL_CHAT_HISTORY

logger = get_logger(__name__)

class GetChatHistoryQuery:
    """
    CQRS Query: Sohbet geçmişini getiren sınıf.
    Bu sınıf hiçbir zaman PostgreSQL (Write Model) tablosuna gitmez.
    Doğrudan Read Model üzerinden (şu an memory, gerçekte Redis/ClickHouse) 
    veriyi okur ve O(1) hızında döndürür.
    """
    
    async def execute(self, user_1: int, user_2: int) -> list:
        logger.info("[GetChatHistoryQuery] Sorgu başlatıldı | u1=%s u2=%s", user_1, user_2)
        
        room_id = f"{min(user_1, user_2)}_{max(user_1, user_2)}"
        
        # Karmaşık JOIN'ler yok. Doğrudan döküman / key-value araması.
        history = READ_MODEL_CHAT_HISTORY.get(room_id, [])
        
        logger.info("[GetChatHistoryQuery] Sonuç bulundu | room_id=%s count=%s", room_id, len(history))
        return history
