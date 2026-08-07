"""
WS bağlantısı kurulurken gönderilecek başlangıç commerce snapshot'ı.

Router'ın auction/direct_sale domain katmanlarına doğrudan erişmesini engeller.
Yeni bir commerce tipi eklendiğinde sadece bu dosya güncellenir.
"""
from __future__ import annotations

from app.use_cases.auctions.queries.auction_queries import GetAuctionStateQuery
from app.use_cases.direct_sales import direct_sale_redis as ds_redis

_DS_INACTIVE = frozenset({"ended", "cancelled"})


async def get_stream_commerce_snapshot(stream_id: int) -> dict:
    """
    Verilen stream için anlık commerce durumunu döner.

    Dönüş:
        {
            "auction":      dict  — her zaman dolu (idle olabilir)
            "direct_sale":  dict | None  — yalnızca aktif/paused/sold_out ise dolu
        }
    """
    auction_state = await GetAuctionStateQuery().execute(stream_id)

    ds_state = await ds_redis.get_state(stream_id)
    active_ds = None
    if ds_state and ds_state.get("status") not in _DS_INACTIVE:
        active_ds = ds_state

    return {"auction": auction_state, "direct_sale": active_ds}
