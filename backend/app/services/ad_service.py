"""
Ad Service — yerel reklam ağı bütçe yönetimi.

Redis, PostgreSQL arasındaki köprüdür:
  - ad_campaign_budget:{id}  → kalan bütçe (TL, float string)
  - ad_campaign_cpc:{id}     → tıklama maliyeti (TL, float string)

Race-condition önleme:
  Bütçe düşme işlemi bir Lua script'i ile atomik olarak yapılır.
  Redis'in tek iş parçacıklı Lua çalıştırma garantisi sayesinde
  GET → hesapla → SET döngüsü bölünemez; iki eş zamanlı tıklama
  asla aynı bütçeyi iki kez harcayamaz.
"""

from __future__ import annotations

import logging
from typing import Optional

from sqlalchemy import select, update

from app.database import AsyncSessionLocal
from app.models.ad_campaign import AdCampaign
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

_BUDGET_KEY = "ad_campaign_budget:{}"
_CPC_KEY = "ad_campaign_cpc:{}"

# Lua script: atomik check-and-decrement.
# Döndürdüğü değer:
#   nil        → key yok (kampanya Redis'te kayıtlı değil)
#   yeni float → düşme başarılı (negatife geçmiş olabilir — caller kontrol eder)
_DEDUCT_SCRIPT = """
local current = tonumber(redis.call('GET', KEYS[1]))
if not current then return nil end
local bid = tonumber(ARGV[1])
local new_val = current - bid
redis.call('SET', KEYS[1], string.format('%.6f', new_val))
return string.format('%.6f', new_val)
"""


async def load_active_campaigns_to_redis() -> int:
    """
    status='active' olan tüm kampanyaları PostgreSQL'den çekip
    kalan bütçelerini (total_budget - spent_budget) Redis'e yükler.

    Bu fonksiyon her 10 dakikada bir ARQ cron job'u olarak çalışır;
    Redis ile PostgreSQL arasındaki olası sapmaları düzeltir ve
    yeni başlatılan kampanyaları da Redis'e ekler.

    Döndürür: yüklenen kampanya sayısı
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(AdCampaign).where(AdCampaign.status == "active")
        )
        campaigns = result.scalars().all()

    if not campaigns:
        logger.info("[AdService] Yüklenecek aktif kampanya yok.")
        return 0

    redis = await get_redis()
    pipe = redis.pipeline()
    for c in campaigns:
        remaining = max(0.0, c.total_budget - c.spent_budget)
        pipe.set(_BUDGET_KEY.format(c.id), f"{remaining:.6f}")
        pipe.set(_CPC_KEY.format(c.id), f"{c.cpc_bid:.6f}")
    await pipe.execute()

    logger.info("[AdService] %d kampanya Redis'e yüklendi.", len(campaigns))
    return len(campaigns)


async def record_ad_click(campaign_id: int, user_id: int) -> bool:
    """
    Bir reklam tıklamasını kaydeder:
      1. Redis'ten cpc_bid'i okur.
      2. Lua script ile bütçeden atomik olarak düşer.
      3. Bütçe ≤ 0 ise:
           - PostgreSQL'de kampanya status='completed', spent_budget=total_budget
           - Redis'ten her iki key'i siler.

    Döndürür:
      True  → tıklama başarıyla kaydedildi
      False → kampanya bulunamadı / bütçe zaten tükenmiş
    """
    redis = await get_redis()
    budget_key = _BUDGET_KEY.format(campaign_id)
    cpc_key = _CPC_KEY.format(campaign_id)

    # cpc_bid'i Redis'ten oku (load_active_campaigns_to_redis tarafından doldurulmuş)
    cpc_str: Optional[str] = await redis.get(cpc_key)
    if cpc_str is None:
        logger.warning(
            "[AdService] cpc key Redis'te yok — kampanya yüklenmemiş ya da tamamlanmış: %d",
            campaign_id,
        )
        return False

    cpc_bid = float(cpc_str)

    # Atomik bütçe düşme
    deduct = redis.register_script(_DEDUCT_SCRIPT)
    result = await deduct(keys=[budget_key], args=[f"{cpc_bid:.6f}"])

    if result is None:
        # budget key yok — kampanya belki daha önce tamamlandı
        logger.warning(
            "[AdService] budget key Redis'te yok: campaign_id=%d", campaign_id
        )
        return False

    new_budget = float(result)

    if new_budget <= 0:
        # Bütçe tükendi — PostgreSQL'de kampanyayı tamamla
        async with AsyncSessionLocal() as db:
            update_result = await db.execute(
                update(AdCampaign)
                .where(
                    AdCampaign.id == campaign_id,
                    AdCampaign.status == "active",   # idempotency guard
                )
                .values(status="completed", spent_budget=AdCampaign.total_budget)
                .returning(AdCampaign.id)
            )
            await db.commit()
            completed_row = update_result.fetchone()

        if completed_row:
            # Sadece bu worker başarıyla güncelledi — key'leri temizle
            pipe = redis.pipeline()
            pipe.delete(budget_key)
            pipe.delete(cpc_key)
            await pipe.execute()
            logger.info(
                "[AdService] Kampanya tamamlandı (bütçe tükendi): id=%d", campaign_id
            )

    return True


async def pause_campaign(campaign_id: int, seller_id: int) -> bool:
    """
    Kampanyayı duraklatır. Sadece kampanya sahibi çağırabilir.
    Redis key'lerini siler (tıklama almaması için).
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            update(AdCampaign)
            .where(
                AdCampaign.id == campaign_id,
                AdCampaign.seller_id == seller_id,
                AdCampaign.status == "active",
            )
            .values(status="paused")
            .returning(AdCampaign.id)
        )
        await db.commit()
        updated = result.fetchone()

    if updated:
        redis = await get_redis()
        pipe = redis.pipeline()
        pipe.delete(_BUDGET_KEY.format(campaign_id))
        pipe.delete(_CPC_KEY.format(campaign_id))
        await pipe.execute()
        return True
    return False


async def resume_campaign(campaign_id: int, seller_id: int) -> bool:
    """
    Duraklatılmış kampanyayı yeniden başlatır.
    Redis'e bütçeyi yeniden yükler.
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            update(AdCampaign)
            .where(
                AdCampaign.id == campaign_id,
                AdCampaign.seller_id == seller_id,
                AdCampaign.status == "paused",
            )
            .values(status="active")
            .returning(AdCampaign.id)
        )
        await db.commit()
        updated = result.fetchone()

    if not updated:
        return False

    # Güncel bütçeyi Redis'e yükle
    async with AsyncSessionLocal() as db:
        campaign = await db.scalar(
            select(AdCampaign).where(AdCampaign.id == campaign_id)
        )
    if campaign:
        remaining = max(0.0, campaign.total_budget - campaign.spent_budget)
        redis = await get_redis()
        pipe = redis.pipeline()
        pipe.set(_BUDGET_KEY.format(campaign_id), f"{remaining:.6f}")
        pipe.set(_CPC_KEY.format(campaign_id), f"{campaign.cpc_bid:.6f}")
        await pipe.execute()

    return True
