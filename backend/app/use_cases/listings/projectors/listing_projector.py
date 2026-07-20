import json
from app.core.events import ListingCreatedEvent
from app.core.logger import get_logger

logger = get_logger(__name__)

# Bu mock bir Read Model'dir. Gerçekte bu Redis (veya ClickHouse) olacaktır.
# test_listing_projectors.py içerisinde sorgulamak için global list kullanıyoruz.
READ_MODEL_LISTINGS_FEED = []

async def project_listing_created(event: ListingCreatedEvent):
    """
    CQRS Projector (Yansıtıcı):
    CreateListingCommand ilan oluşturduğunda (Write Model), bu fonsiyon tetiklenir.
    Görevi: Veriyi, Feed ve Search ekranlarında en hızlı şekilde (O(1)) okunacak 
    formata dönüştürüp Read Model'e kaydetmektir.
    """
    logger.info("[ListingProjector] Event yakalandı: listing_id=%s. Read Model (Feed) güncelleniyor...", event.listing_id)
    
    # Sadece okuma arayüzüne (Frontend Feed) gidecek kadar temiz ve düz veri.
    # JOIN yapmamak için gereken her şeyi buraya ekliyoruz.
    read_data = {
        "id": event.listing_id,
        "seller_id": event.user_id,
        "title": event.title,
        "category": event.category,
        "price": event.price,
        "is_active": True, # Varsayılan olarak aktif
        "likes_count": 0,
        "view_count": 0
    }
    
    # En yeni ilan en başa gelsin diye insert(0)
    READ_MODEL_LISTINGS_FEED.insert(0, read_data)
    
    logger.info("[ListingProjector] Feed Read Model güncellendi | Toplam İlan: %s", len(READ_MODEL_LISTINGS_FEED))

def register_listing_projectors():
    from app.core.event_bus import event_bus
    event_bus.subscribe(ListingCreatedEvent, project_listing_created)
    logger.info("[Projectors] ListingProjector EventBus'a kaydedildi.")
