import asyncio
import logging
import sys
from pathlib import Path

# PYTHONPATH ayarı (backend dizininden çalıştırılabilmesi için)
sys.path.append(str(Path(__file__).parent.parent))

from app.database_clickhouse import get_clickhouse_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MUTATIONS = [
    "ALTER TABLE search_events UPDATE category = 'books' WHERE category IN ('kitap', 'kitap-hobi')",
    "ALTER TABLE search_events UPDATE category = 'home' WHERE category IN ('ev', 'ev-yasam', 'ev_esyalari')",
    "ALTER TABLE search_events UPDATE category = 'sports' WHERE category IN ('spor', 'spor-outdoor')",
    "ALTER TABLE search_events UPDATE category = 'other' WHERE category IN ('diger', 'oyuncak', 'koleksiyonluk', 'muzik_aleti')",
    "ALTER TABLE search_events UPDATE category = 'real_estate' WHERE category = 'emlak'",
    "ALTER TABLE search_events UPDATE category = 'fashion' WHERE category IN ('giyim-aksesuar', 'giyim')",
    "ALTER TABLE search_events UPDATE category = 'vehicles' WHERE category = 'vasita'",
    "ALTER TABLE search_events UPDATE category = 'electronics' WHERE category = 'elektronik'"
]

async def main():
    logger.info("ClickHouse'a bağlanılıyor...")
    ch = await get_clickhouse_client()
    if not ch:
        logger.error("ClickHouse bağlantısı başarısız oldu!")
        return

    logger.info("Mutasyonlar başlatılıyor...")
    for query in MUTATIONS:
        logger.info(f"Çalıştırılıyor: {query}")
        await ch.command(query)
    
    logger.info("Tüm mutasyon komutları başarıyla ClickHouse'a iletildi.")
    logger.info("Not: ClickHouse mutasyonları arka planda (background) asenkron olarak gerçekleştirir.")
    logger.info("Büyük tablolarda verilerin tamamen değişmesi birkaç saniye/dakika sürebilir.")

if __name__ == "__main__":
    asyncio.run(main())
