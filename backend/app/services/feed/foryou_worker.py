import logging
import json
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.enums import UserStatus
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

async def populate_foryou_feed_task(ctx: dict) -> None:
    """
    Her aktif kullanıcının ilgi alanlarını ve BPR verilerini değerlendirip
    'Sana Özel' Redis listesini (feed:{user_id}:foryou) baştan doldurur.
    """
    try:
        redis = await get_redis()
        
        async with AsyncSessionLocal() as db:
            # Sadece aktif kullanıcıları al (gerçek bir senaryoda son 1 ayda girenler vb. filtrelenebilir)
            result = await db.execute(select(User.id).where(User.status == UserStatus.ACTIVE))
            users = result.scalars().all()
            
            for uid in users:
                # 1. BPR (Collaborative Filtering) verilerini al
                bpr_key = f"bpr:rec:{uid}"
                bpr_data = await redis.get(bpr_key)
                bpr_listings = json.loads(bpr_data) if bpr_data else []
                
                # 2. Base Havuz (En Yeni İlanlar)
                recent_listings = await redis.zrevrange("feed:recent", 0, 500)
                recent_listings = [int(lid) for lid in recent_listings]
                
                # 3. BPR ve Recent'i birleştir (BPR öncelikli)
                combined_pool = []
                for lid in bpr_listings:
                    if lid not in combined_pool:
                        combined_pool.append(lid)
                        
                for lid in recent_listings:
                    if lid not in combined_pool:
                        combined_pool.append(lid)
                
                # 4. Greedy Diversity (MAX_PER_SUBCAT = 2)
                final_feed = []
                subcat_counts = {}
                
                for lid in combined_pool:
                    if len(final_feed) >= 500:
                        break
                        
                    listing_data_raw = await redis.get(f"listing:{lid}")
                    if not listing_data_raw:
                        continue
                        
                    listing_data = json.loads(listing_data_raw)
                    if listing_data.get("status") != "active":
                        continue
                        
                    subcat = listing_data.get("subcategory")
                    if subcat:
                        if subcat_counts.get(subcat, 0) >= 2:
                            continue
                        subcat_counts[subcat] = subcat_counts.get(subcat, 0) + 1
                    
                    final_feed.append(lid)
                
                # 5. Sonuçları listeye bas
                if final_feed:
                    foryou_key = f"feed:{uid}:foryou"
                    await redis.delete(foryou_key)
                    # Listeye en baştan eleman eklemek (O(1)) yerine toplu RPUSH ile dizilişi koruyalım
                    # final_feed zaten en önemliden aza doğru (BPR -> Recent)
                    await redis.rpush(foryou_key, *final_feed)
                
        logger.info(f"[ForYouWorker] Sana Özel feed'leri {len(users)} kullanıcı için yenilendi.")
    except Exception as e:
        logger.error(f"[ForYouWorker] Hata: {e}", exc_info=True)
        raise
