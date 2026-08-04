import asyncio
import logging
import sys
from pathlib import Path

# PYTHONPATH ayarı (backend dizininden çalıştırılabilmesi için)
sys.path.append(str(Path(__file__).parent.parent))

from app.database_clickhouse import get_clickhouse_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def main():
    logger.info("ClickHouse'a bağlanılıyor...")
    ch = await get_clickhouse_client()
    if not ch:
        logger.error("ClickHouse bağlantısı başarısız oldu!")
        return

    logger.info("Geçici tablo (search_events_new) oluşturuluyor...")
    await ch.command("CREATE TABLE IF NOT EXISTS search_events_new AS search_events")
    
    logger.info("Eski tablodaki veriler dönüştürülerek yeni tabloya kopyalanıyor...")
    # ClickHouse transform() fonksiyonu ile category primary/sorting key olduğu için
    # veriyi taşırken kopyalıyoruz (Cannot UPDATE key column hatasını aşmak için)
    query = """
    INSERT INTO search_events_new
    SELECT 
        timestamp, 
        user_id, 
        query, 
        transform(category, 
            ['kitap', 'kitap-hobi', 'ev', 'ev-yasam', 'ev_esyalari', 'spor', 'spor-outdoor', 'diger', 'oyuncak', 'koleksiyonluk', 'muzik_aleti', 'emlak', 'giyim-aksesuar', 'giyim', 'vasita', 'elektronik'], 
            ['books', 'books', 'home', 'home', 'home', 'sports', 'sports', 'other', 'other', 'other', 'other', 'real_estate', 'fashion', 'fashion', 'vehicles', 'electronics'], 
            category
        ) AS category,
        result_count,
        intent,
        subcategory
    FROM search_events
    """
    await ch.command(query)

    logger.info("Tabloların isimleri (swap) değiştiriliyor...")
    await ch.command("RENAME TABLE search_events TO search_events_old, search_events_new TO search_events")
    
    logger.info("Eski (eski kategorili) tablo siliniyor...")
    await ch.command("DROP TABLE search_events_old")
    
    logger.info("İşlem başarıyla tamamlandı! Tüm veriler yeni kategorileriyle güncellendi.")

if __name__ == "__main__":
    asyncio.run(main())
