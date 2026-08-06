"""
DirectSale Redis katmanı — LIFECYCLE cache yönetimi.

Keys (her stream için):
  direct_sale:{stream_id}:state  → Hash  — aktif satış snapshot'ı
  direct_sale:{stream_id}:stock  → String (int) — kalan stok, atomik azaltma

Lua dönüş değerleri (decrement_stock):
  -1  → key bulunamadı (satış Redis'te yok)
  -2  → yetersiz stok (purchase reddedildi, stok değişmedi)
  >=0 → kalan stok (0 = son adet satıldı → sold_out akışı başlar)
"""

from __future__ import annotations
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# ── Key yardımcıları ──────────────────────────────────────────────────────────

def _state_key(stream_id: int) -> str:
    return f"direct_sale:{stream_id}:state"

def _stock_key(stream_id: int) -> str:
    return f"direct_sale:{stream_id}:stock"

# ── Lua — atomik stok azaltma ─────────────────────────────────────────────────
# KEYS[1] = direct_sale:{stream_id}:stock
# ARGV[1] = istenen miktar
# Dönüş: -1 (bulunamadı) | -2 (yetersiz) | >=0 (kalan stok)

_DECREMENT_STOCK_SCRIPT = """
local current = tonumber(redis.call('GET', KEYS[1]))
if current == nil then return -1 end
if current < tonumber(ARGV[1]) then return -2 end
local remaining = current - tonumber(ARGV[1])
redis.call('SET', KEYS[1], remaining)
return remaining
"""

# ── State geçişleri ───────────────────────────────────────────────────────────

async def start_sale(stream_id: int, sale_id: int, title: str, price: float,
                     total_stock: int, product_image_url: Optional[str],
                     proof_image_url: Optional[str]) -> None:
    """Yeni satış başlat: hash + stock key'lerini yükle."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    state_key = _state_key(stream_id)
    stock_key = _stock_key(stream_id)

    await redis.hset(state_key, mapping={
        "sale_id":           str(sale_id),
        "status":            "active",
        "title":             title,
        "price":             str(price),
        "total_stock":       str(total_stock),
        "remaining_stock":   str(total_stock),
        "product_image_url": product_image_url or "",
        "proof_image_url":   proof_image_url or "",
        "end_reason":        "",
    })
    await redis.set(stock_key, total_stock)

    # LIFECYCLE: akış kapanınca veya satış bitince silinir
    _ttl = 24 * 3600
    await redis.expire(state_key, _ttl)
    await redis.expire(stock_key, _ttl)


async def pause_sale(stream_id: int) -> None:
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), "status", "paused")


async def resume_sale(stream_id: int) -> None:
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), "status", "active")


async def set_sold_out(stream_id: int) -> None:
    """Stok sıfırlandı — status'u sold_out yap (key'ler henüz silinmez)."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), "status", "sold_out")


async def end_sale(stream_id: int, end_reason: str) -> None:
    """Satışı sonlandır ve LIFECYCLE key'lerini temizle."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), mapping={
        "status":     "ended",
        "end_reason": end_reason,
    })
    await redis.delete(_state_key(stream_id), _stock_key(stream_id))


async def cancel_sale(stream_id: int) -> None:
    """Satışı iptal et ve LIFECYCLE key'lerini temizle."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), "status", "cancelled")
    await redis.delete(_state_key(stream_id), _stock_key(stream_id))


async def decrement_stock(stream_id: int, quantity: int) -> int:
    """
    Atomik stok azaltma. Dönüş:
      -1  → satış Redis'te yok
      -2  → yetersiz stok
      >=0 → kalan stok (0 = sold_out tetiklenir)
    """
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    script = redis.register_script(_DECREMENT_STOCK_SCRIPT)
    result = await script(keys=[_stock_key(stream_id)], args=[quantity])
    return int(result)


async def update_remaining_stock(stream_id: int, remaining: int) -> None:
    """Hash'teki remaining_stock alanını güncelle (purchase sonrası sync)."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    await redis.hset(_state_key(stream_id), "remaining_stock", str(remaining))


# ── Okuma ─────────────────────────────────────────────────────────────────────

async def get_state(stream_id: int) -> Optional[dict]:
    """
    Redis hash'ten güncel satış state'ini döner.
    Aktif satış yoksa None döner.
    """
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    data = await redis.hgetall(_state_key(stream_id))
    if not data:
        return None
    return {
        "sale_id":           int(data[b"sale_id"]),
        "status":            data[b"status"].decode(),
        "title":             data[b"title"].decode(),
        "price":             float(data[b"price"]),
        "total_stock":       int(data[b"total_stock"]),
        "remaining_stock":   int(data[b"remaining_stock"]),
        "product_image_url": data[b"product_image_url"].decode() or None,
        "proof_image_url":   data[b"proof_image_url"].decode() or None,
        "end_reason":        data[b"end_reason"].decode() or None,
    }


# ── WS yayını ─────────────────────────────────────────────────────────────────

async def publish_direct_sale(stream_id: int, payload: dict) -> None:
    """
    Direct sale event'ini tüm stream viewer'larına yayınlar.
    Auction broadcast kanalını yeniden kullanır — aynı WS bağlantısı,
    event type field'i ile ayrışır.
    """
    from app.use_cases.auctions.auction_utils import broadcast_to_stream_viewers
    await broadcast_to_stream_viewers(stream_id, payload)
