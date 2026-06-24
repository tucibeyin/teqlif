"""
Ad Service — yerel reklam ağı bütçe yönetimi.

Redis, PostgreSQL arasındaki köprüdür:
  - ad_campaign_budget:{id}  → kalan bütçe (TUCi, integer string)
  - ad_campaign_cpc:{id}     → tıklama maliyeti (TUCi, integer string)

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

# Lua script: atomik check-and-decrement (TUCi, integer).
# Döndürdüğü değer:
#   nil    → key yok (kampanya Redis'te kayıtlı değil)
#   yeni int string → düşme başarılı (negatife geçmiş olabilir — caller kontrol eder)
_DEDUCT_SCRIPT = """
local current = tonumber(redis.call('GET', KEYS[1]))
if not current then return nil end
local bid = tonumber(ARGV[1])
local new_val = math.floor(current - bid)
redis.call('SET', KEYS[1], tostring(new_val))
return tostring(new_val)
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
        remaining = max(0, c.total_budget - c.spent_budget)
        pipe.set(_BUDGET_KEY.format(c.id), str(remaining))
        pipe.set(_CPC_KEY.format(c.id), str(c.cpc_bid))
    await pipe.execute()

    logger.info("[AdService] %d kampanya Redis'e yüklendi.", len(campaigns))
    return len(campaigns)


async def _reload_campaign_to_redis(campaign_id: int) -> Optional[int]:
    """
    Tek bir kampanyayı PostgreSQL'den okuyup Redis'e yükler.
    Döndürür: cpc_bid (başarılıysa) veya None (kampanya yoksa/bitişse).
    """
    async with AsyncSessionLocal() as db:
        campaign = await db.scalar(
            select(AdCampaign).where(
                AdCampaign.id == campaign_id,
                AdCampaign.status == "active",
            )
        )
    if not campaign:
        return None
    remaining = max(0, campaign.total_budget - campaign.spent_budget)
    redis = await get_redis()
    pipe = redis.pipeline()
    pipe.set(_BUDGET_KEY.format(campaign_id), str(remaining))
    pipe.set(_CPC_KEY.format(campaign_id), str(campaign.cpc_bid))
    await pipe.execute()
    logger.info("[AdService] Kampanya Redis'e yeniden yüklendi: id=%d remaining=%d TUCi", campaign_id, remaining)
    return campaign.cpc_bid


async def record_ad_click(campaign_id: int, user_id: int) -> bool:
    """
    Bir reklam tıklamasını kaydeder:
      1. Redis'ten cpc_bid'i okur; key yoksa PostgreSQL'den yeniden yükler.
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

    # cpc_bid'i Redis'ten oku; key yoksa PostgreSQL'den sıcak yükle
    cpc_str: Optional[str] = await redis.get(cpc_key)
    if cpc_str is None:
        logger.warning(
            "[AdService] cpc key Redis'te yok — PostgreSQL'den yeniden yükleniyor: %d",
            campaign_id,
        )
        reloaded_cpc = await _reload_campaign_to_redis(campaign_id)
        if reloaded_cpc is None:
            logger.warning("[AdService] Kampanya aktif değil ya da bulunamadı: %d", campaign_id)
            return False
        cpc_str = str(reloaded_cpc)

    cpc_bid = int(cpc_str)

    # Atomik bütçe düşme
    deduct = redis.register_script(_DEDUCT_SCRIPT)
    result = await deduct(keys=[budget_key], args=[str(cpc_bid)])

    if result is None:
        # budget key yok — kampanya belki daha önce tamamlandı
        logger.warning(
            "[AdService] budget key Redis'te yok: campaign_id=%d", campaign_id
        )
        return False

    new_budget = int(result)

    # Her tıklamada spent_budget'ı PostgreSQL'e yansıt (fire-and-forget)
    async def _sync_spent() -> None:
        try:
            async with AsyncSessionLocal() as db:
                await db.execute(
                    update(AdCampaign)
                    .where(AdCampaign.id == campaign_id, AdCampaign.status == "active")
                    .values(spent_budget=AdCampaign.spent_budget + cpc_bid)
                )
                await db.commit()
        except Exception as exc:
            logger.warning("[AdService] spent_budget DB sync başarısız: campaign=%d %s", campaign_id, exc)

    import asyncio
    asyncio.create_task(_sync_spent())

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
        remaining = max(0, campaign.total_budget - campaign.spent_budget)
        redis = await get_redis()
        pipe = redis.pipeline()
        pipe.set(_BUDGET_KEY.format(campaign_id), str(remaining))
        pipe.set(_CPC_KEY.format(campaign_id), str(campaign.cpc_bid))
        await pipe.execute()

    return True
