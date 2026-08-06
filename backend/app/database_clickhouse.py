"""
ClickHouse bağlantı katmanı — Redis-buffered batch insert pattern.

INSERT akışı (endüstri standardı):
  buffer_*() → Redis list (ch_buf:{table}) → _flush_loop() her FLUSH_INTERVAL s → batch INSERT

  Her single-row insert 1 MergeTree part oluşturur; binlerce part birikiyor ve
  background merge disk'i eziyor. Buffer + batch flush bu sorunu ortadan kaldırır.

Read/query kullanımı değişmez: SELECT sorgular doğrudan ClickHouse'a gider.
Batch insert endpoint'leri (feed_analytics, swipe_live_events) değişmez — zaten toplu.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Optional

import clickhouse_connect
from clickhouse_connect.driver.asyncclient import AsyncClient
from app.core.circuit_breaker import clickhouse_breaker, CircuitOpenError

logger = logging.getLogger(__name__)

# ── Singleton ─────────────────────────────────────────────────────────────────

_client: Optional[AsyncClient] = None
_flush_task: Optional[asyncio.Task] = None

# ── Ayarlar ───────────────────────────────────────────────────────────────────

FLUSH_INTERVAL: int = 5    # saniye — her 5s bir flush
MAX_BATCH: int = 2000      # flush başına tablo başına max satır

# Redis buffer key'leri
_BUF_USER_EVENTS         = "ch_buf:user_events"
_BUF_SEARCH_EVENTS       = "ch_buf:search_events"
_BUF_DIRECT_SALE_EVENTS  = "ch_buf:direct_sale_events"

# ── Tablo DDL ─────────────────────────────────────────────────────────────────

_CREATE_USER_EVENTS_TABLE = """
CREATE TABLE IF NOT EXISTS user_events
(
    user_id          Nullable(UInt32),
    item_id          UInt32,
    item_type        LowCardinality(String),
    event_type       LowCardinality(String),
    price_point      Nullable(Float64),
    duration_seconds Nullable(Float64),
    metadata         String DEFAULT '',
    timestamp        DateTime DEFAULT now(),
    subcategory      LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, item_id)
SETTINGS index_granularity = 8192
"""

_ALTER_USER_EVENTS = [
    "ALTER TABLE user_events ADD COLUMN IF NOT EXISTS metadata String DEFAULT ''",
    "ALTER TABLE user_events ADD COLUMN IF NOT EXISTS subcategory LowCardinality(String) DEFAULT ''",
]

_CREATE_FEED_ANALYTICS_TABLE = """
CREATE TABLE IF NOT EXISTS feed_analytics
(
    timestamp           DateTime,
    user_id             String,
    listing_id          String,
    event_type          LowCardinality(String),
    dwell_time_ms       UInt32,
    content_type        LowCardinality(String) DEFAULT '',
    slot_index          UInt32 DEFAULT 0,
    stream_category     LowCardinality(String) DEFAULT '',
    listing_condition   LowCardinality(String) DEFAULT '',
    listing_subcategory LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (listing_id, event_type, timestamp)
"""

_ALTER_FEED_ANALYTICS = [
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS content_type LowCardinality(String) DEFAULT ''",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS slot_index UInt32 DEFAULT 0",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS stream_category LowCardinality(String) DEFAULT ''",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS listing_condition LowCardinality(String) DEFAULT ''",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS listing_subcategory LowCardinality(String) DEFAULT ''",
]

_CREATE_SEARCH_EVENTS_TABLE = """
CREATE TABLE IF NOT EXISTS search_events
(
    timestamp    DateTime,
    user_id      Nullable(UInt32),
    query        String,
    category     LowCardinality(String) DEFAULT '',
    result_count UInt32 DEFAULT 0,
    intent       LowCardinality(String) DEFAULT '',
    subcategory  LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (category, timestamp)
"""

_ALTER_SEARCH_EVENTS = [
    "ALTER TABLE search_events ADD COLUMN IF NOT EXISTS intent LowCardinality(String) DEFAULT ''",
    "ALTER TABLE search_events ADD COLUMN IF NOT EXISTS subcategory LowCardinality(String) DEFAULT ''",
]

_CREATE_SWIPE_LIVE_EVENTS_TABLE = """
CREATE TABLE IF NOT EXISTS swipe_live_events
(
    user_id              UInt32,
    stream_id            UInt32        DEFAULT 0,
    listing_id           UInt32        DEFAULT 0,
    event_type           LowCardinality(String),
    dwell_ms             UInt32        DEFAULT 0,
    stream_category      LowCardinality(String) DEFAULT '',
    listing_category     LowCardinality(String) DEFAULT '',
    listing_condition    LowCardinality(String) DEFAULT '',
    listings_seen        UInt8         DEFAULT 0,
    slot_index           UInt32        DEFAULT 0,
    session_id           String        DEFAULT '',
    timestamp            DateTime      DEFAULT now(),
    stream_subcategory   LowCardinality(String) DEFAULT '',
    listing_subcategory  LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp)
SETTINGS index_granularity = 8192
"""

_CREATE_DIRECT_SALE_EVENTS_TABLE = """
CREATE TABLE IF NOT EXISTS direct_sale_events
(
    event_id                UUID DEFAULT generateUUIDv4(),
    event_type              LowCardinality(String),
    sale_id                 UInt32,
    stream_id               UInt32,
    host_id                 UInt32,
    user_id                 UInt32,
    order_id                Nullable(UInt32),
    listing_id              Nullable(UInt32),
    category                LowCardinality(Nullable(String)),
    quantity                Nullable(UInt8),
    unit_price              Nullable(Decimal(10, 2)),
    total_price             Nullable(Decimal(10, 2)),
    remaining_stock_before  Nullable(UInt16),
    remaining_stock_after   Nullable(UInt16),
    viewer_count            Nullable(UInt32),
    end_reason              LowCardinality(Nullable(String)),
    orders_voided           Nullable(Bool),
    created_at              DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (sale_id, created_at, event_type)
SETTINGS index_granularity = 8192
"""

_ALTER_SWIPE_LIVE_EVENTS = [
    "ALTER TABLE swipe_live_events ADD COLUMN IF NOT EXISTS listing_condition LowCardinality(String) DEFAULT ''",
    "ALTER TABLE swipe_live_events ADD COLUMN IF NOT EXISTS stream_subcategory LowCardinality(String) DEFAULT ''",
    "ALTER TABLE swipe_live_events ADD COLUMN IF NOT EXISTS listing_subcategory LowCardinality(String) DEFAULT ''",
]

# ── Bağlantı ──────────────────────────────────────────────────────────────────

async def get_clickhouse_client() -> AsyncClient | None:
    """Singleton AsyncClient döndürür. Circuit açıksa None döner."""
    global _client
    try:
        await clickhouse_breaker.__aenter__()
    except CircuitOpenError:
        logger.warning("[ClickHouse] Circuit açık — istek atlandı")
        return None
    if _client is None:
        try:
            _client = await clickhouse_connect.get_async_client(
                host="localhost",
                port=8123,
                connect_timeout=5,
                send_receive_timeout=30,
            )
            await clickhouse_breaker.__aexit__(None, None, None)
        except Exception as exc:
            await clickhouse_breaker.__aexit__(type(exc), exc, None)
            logger.warning("[ClickHouse] Bağlantı kurulamadı | %s", exc)
            return None
    else:
        await clickhouse_breaker.__aexit__(None, None, None)
    return _client


async def init_clickhouse() -> None:
    """Startup: bağlantı kur + tablolar oluştur."""
    global _client
    try:
        _client = await clickhouse_connect.get_async_client(
            host="localhost",
            port=8123,
            connect_timeout=5,
            send_receive_timeout=30,
        )
        await _client.command(_CREATE_USER_EVENTS_TABLE)
        for stmt in _ALTER_USER_EVENTS:
            await _client.command(stmt)
        await _client.command(_CREATE_FEED_ANALYTICS_TABLE)
        for stmt in _ALTER_FEED_ANALYTICS:
            await _client.command(stmt)
        await _client.command(_CREATE_SEARCH_EVENTS_TABLE)
        for stmt in _ALTER_SEARCH_EVENTS:
            await _client.command(stmt)
        await _client.command(_CREATE_SWIPE_LIVE_EVENTS_TABLE)
        for stmt in _ALTER_SWIPE_LIVE_EVENTS:
            await _client.command(stmt)
        await _client.command(_CREATE_DIRECT_SALE_EVENTS_TABLE)
        logger.info("[ClickHouse] Bağlantı kuruldu, tablolar hazır.")
    except Exception as exc:
        logger.warning(
            "[ClickHouse] Başlatma başarısız — servis kapalı olabilir. "
            "PostgreSQL akışı etkilenmez. Hata: %s",
            exc,
        )
        _client = None


async def close_clickhouse() -> None:
    """Shutdown: bağlantıyı temizle."""
    global _client
    if _client is not None:
        await _client.close()
        _client = None
        logger.info("[ClickHouse] Bağlantı kapatıldı.")

# ── Buffer API — yazma noktası ────────────────────────────────────────────────

def _now_str() -> str:
    """ClickHouse DateTime formatında UTC timestamp."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


async def buffer_user_event(
    *,
    event_type: str,
    item_id: int,
    item_type: str,
    user_id: Optional[int] = None,
    price_point: Optional[float] = None,
    duration_seconds: Optional[float] = None,
    subcategory: str = "",
) -> None:
    """
    user_events Redis buffer'ına ekler (< 1ms). Fire-and-forget.
    Timestamp event anında alınır — flush anında değil.
    Row format: [user_id, item_id, item_type, event_type, price_point, duration_seconds, timestamp, subcategory]
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        row = [user_id, item_id, item_type, event_type,
               price_point, duration_seconds, _now_str(), subcategory]
        await redis.rpush(_BUF_USER_EVENTS, json.dumps(row))
    except Exception as exc:
        logger.warning("[ClickHouse] buffer_user_event başarısız: %s", exc)


async def buffer_search_event(
    *,
    user_id: Optional[int],
    query: str,
    category: str = "",
    result_count: int = 0,
    intent: str = "",
    subcategory: str = "",
) -> None:
    """search_events Redis buffer'ına ekler.
    Row format: [timestamp, user_id, query, category, result_count, intent, subcategory]
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        row = [_now_str(), user_id, query, category, result_count, intent, subcategory]
        await redis.rpush(_BUF_SEARCH_EVENTS, json.dumps(row))
    except Exception as exc:
        logger.warning("[ClickHouse] buffer_search_event başarısız: %s", exc)


async def buffer_direct_sale_event(
    *,
    event_type: str,
    sale_id: int,
    stream_id: int,
    host_id: int,
    user_id: int = 0,
    order_id: Optional[int] = None,
    listing_id: Optional[int] = None,
    category: Optional[str] = None,
    quantity: Optional[int] = None,
    unit_price: Optional[float] = None,
    total_price: Optional[float] = None,
    remaining_stock_before: Optional[int] = None,
    remaining_stock_after: Optional[int] = None,
    viewer_count: Optional[int] = None,
    end_reason: Optional[str] = None,
    orders_voided: Optional[bool] = None,
) -> None:
    """direct_sale_events Redis buffer'ına ekler (< 1ms). Fire-and-forget."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        row = [
            event_type, sale_id, stream_id, host_id, user_id,
            order_id, listing_id, category, quantity,
            unit_price, total_price, remaining_stock_before,
            remaining_stock_after, viewer_count, end_reason,
            orders_voided, _now_str(),
        ]
        await redis.rpush(_BUF_DIRECT_SALE_EVENTS, json.dumps(row))
    except Exception as exc:
        logger.warning("[ClickHouse] buffer_direct_sale_event başarısız: %s", exc)


# Backward-compat alias — eski call site'ları kırmaz
async def track_user_event(
    *,
    event_type: str,
    item_id: int,
    item_type: str,
    user_id: Optional[int] = None,
    price_point: Optional[float] = None,
    duration_seconds: Optional[float] = None,
) -> None:
    await buffer_user_event(
        event_type=event_type,
        item_id=item_id,
        item_type=item_type,
        user_id=user_id,
        price_point=price_point,
        duration_seconds=duration_seconds,
    )


# ── Batch insert — toplu flush endpoint'leri (değişmez) ──────────────────────

async def batch_insert_swipe_live_events(events: list[dict]) -> None:
    """swipe_live_events — zaten toplu, doğrudan insert edilir."""
    if _client is None or not events:
        return
    cols = [
        "user_id", "stream_id", "listing_id", "event_type", "dwell_ms",
        "stream_category", "listing_category", "listing_condition",
        "listings_seen", "slot_index", "session_id",
        "stream_subcategory", "listing_subcategory",
    ]
    rows = [
        [
            e.get("user_id", 0),
            e.get("stream_id", 0),
            e.get("listing_id", 0),
            e.get("event_type", ""),
            e.get("dwell_ms", 0),
            e.get("stream_category", ""),
            e.get("listing_category", ""),
            e.get("listing_condition", ""),
            e.get("listings_seen", 0),
            e.get("slot_index", 0),
            e.get("session_id", ""),
            e.get("stream_subcategory", ""),
            e.get("listing_subcategory", ""),
        ]
        for e in events
    ]
    try:
        await _client.insert("swipe_live_events", rows, column_names=cols)
    except Exception as exc:
        logger.warning("[ClickHouse] batch_insert_swipe_live_events başarısız | count=%d | %s", len(events), exc)

# ── Flush motoru ──────────────────────────────────────────────────────────────

def _parse_dt(val) -> datetime:
    """Redis'ten gelen timestamp string'ini naive datetime'a çevirir."""
    if isinstance(val, datetime):
        return val.replace(tzinfo=None)
    try:
        return datetime.strptime(str(val), "%Y-%m-%d %H:%M:%S")
    except Exception:
        return datetime.utcnow()


async def _drain(redis, buf_key: str) -> list[list]:
    """Buffer'dan atomik olarak MAX_BATCH satır çeker, kalanı bırakır."""
    async with redis.pipeline(transaction=True) as pipe:
        await pipe.lrange(buf_key, 0, MAX_BATCH - 1)
        await pipe.ltrim(buf_key, MAX_BATCH, -1)
        results = await pipe.execute()
    out = []
    for raw in results[0]:
        try:
            out.append(json.loads(raw))
        except Exception:
            continue
    return out


async def flush_all_buffers() -> None:
    """
    Tüm buffer'ları boşaltır ve ClickHouse'a batch insert yapar.
    Hata oluşursa satırlar kaybedilir (analytics fire-and-forget kabul edilebilir).
    Finansal veri için bu pattern kullanılmamalıdır.
    """
    if _client is None:
        return

    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()

        # ── user_events ────────────────────────────────────────────────────────
        # Row format: [user_id, item_id, item_type, event_type, price_point, duration_seconds, timestamp, subcategory?]
        rows = await _drain(redis, _BUF_USER_EVENTS)
        if rows:
            data = [
                [
                    r[0],                                      # user_id
                    int(r[1]),                                 # item_id
                    str(r[2]),                                 # item_type
                    str(r[3]),                                 # event_type
                    r[4],                                      # price_point
                    r[5],                                      # duration_seconds
                    _parse_dt(r[6]),                           # timestamp
                    str(r[7]) if len(r) > 7 else "",           # subcategory (yeni alan)
                ]
                for r in rows
            ]
            await _client.insert(
                "user_events",
                data,
                column_names=[
                    "user_id", "item_id", "item_type", "event_type",
                    "price_point", "duration_seconds", "timestamp", "subcategory",
                ],
            )
            logger.debug("[ClickHouse] user_events flush | %d satır", len(data))

        # ── search_events ──────────────────────────────────────────────────────
        # Row format: [timestamp, user_id, query, category, result_count, intent, subcategory?]
        rows = await _drain(redis, _BUF_SEARCH_EVENTS)
        if rows:
            data = [
                [
                    _parse_dt(r[0]),                           # timestamp
                    r[1],                                      # user_id
                    str(r[2]),                                 # query
                    str(r[3]),                                 # category
                    int(r[4]),                                 # result_count
                    str(r[5]) if len(r) > 5 else "",           # intent
                    str(r[6]) if len(r) > 6 else "",           # subcategory (yeni alan)
                ]
                for r in rows
            ]
            await _client.insert(
                "search_events",
                data,
                column_names=["timestamp", "user_id", "query", "category", "result_count", "intent", "subcategory"],
            )
            logger.debug("[ClickHouse] search_events flush | %d satır", len(data))

        # ── direct_sale_events ────────────────────────────────────────────────
        # Row format: [event_type, sale_id, stream_id, host_id, user_id, order_id,
        #              listing_id, category, quantity, unit_price, total_price,
        #              remaining_stock_before, remaining_stock_after, viewer_count,
        #              end_reason, orders_voided, created_at]
        rows = await _drain(redis, _BUF_DIRECT_SALE_EVENTS)
        if rows:
            data = [
                [
                    str(r[0]),                                        # event_type
                    int(r[1]),                                        # sale_id
                    int(r[2]),                                        # stream_id
                    int(r[3]),                                        # host_id
                    int(r[4]),                                        # user_id
                    int(r[5]) if r[5] is not None else None,          # order_id
                    int(r[6]) if r[6] is not None else None,          # listing_id
                    str(r[7]) if r[7] else None,                      # category
                    int(r[8]) if r[8] is not None else None,          # quantity
                    float(r[9]) if r[9] is not None else None,        # unit_price
                    float(r[10]) if r[10] is not None else None,      # total_price
                    int(r[11]) if r[11] is not None else None,        # remaining_stock_before
                    int(r[12]) if r[12] is not None else None,        # remaining_stock_after
                    int(r[13]) if r[13] is not None else None,        # viewer_count
                    str(r[14]) if r[14] else None,                    # end_reason
                    bool(r[15]) if r[15] is not None else None,       # orders_voided
                    _parse_dt(r[16]),                                  # created_at
                ]
                for r in rows
            ]
            await _client.insert(
                "direct_sale_events",
                data,
                column_names=[
                    "event_type", "sale_id", "stream_id", "host_id", "user_id",
                    "order_id", "listing_id", "category", "quantity",
                    "unit_price", "total_price", "remaining_stock_before",
                    "remaining_stock_after", "viewer_count", "end_reason",
                    "orders_voided", "created_at",
                ],
            )
            logger.debug("[ClickHouse] direct_sale_events flush | %d satır", len(data))

    except Exception as exc:
        logger.warning("[ClickHouse] flush_all_buffers başarısız: %s", exc)


async def _flush_loop() -> None:
    """FLUSH_INTERVAL saniyede bir flush_all_buffers çalıştırır."""
    while True:
        try:
            await asyncio.sleep(FLUSH_INTERVAL)
            await flush_all_buffers()
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("[ClickHouse] flush_loop beklenmedik hata: %s", exc)


def start_flush_loop() -> asyncio.Task:
    """FastAPI lifespan startup'ından çağrılır."""
    global _flush_task
    _flush_task = asyncio.create_task(_flush_loop(), name="ch_flush_loop")
    logger.info("[ClickHouse] Flush loop başlatıldı (interval=%ds, batch=%d)", FLUSH_INTERVAL, MAX_BATCH)
    return _flush_task


async def stop_flush_loop() -> None:
    """FastAPI lifespan shutdown'ında çağrılır: döngüyü durdurur + son flush."""
    global _flush_task
    if _flush_task is not None:
        _flush_task.cancel()
        try:
            await _flush_task
        except asyncio.CancelledError:
            pass
        _flush_task = None
    await flush_all_buffers()
    logger.info("[ClickHouse] Flush loop durduruldu, son flush tamamlandı.")


# ── Faz 6 — Fiyat önerisi + Talep tahmini ────────────────────────────────────

async def get_direct_sale_suggestions(
    host_id: int,
    listing_id: Optional[int] = None,
    lookback_days: int = 90,
    min_samples: int = 3,
) -> dict:
    """
    Faz 6.1 + 6.2: host'un geçmiş direct satışlarından fiyat önerisi ve talep
    tahmini hesaplar. ClickHouse devre dışıysa veya veri yoksa boş döner.

    Dönen dict:
      suggested_price      - geçmiş satış ortalama fiyatı (float | None)
      avg_conversion_rate  - ort. dönüşüm oranı 0-1 (float | None)
      avg_demand           - ort. satılan adet (float | None)
      recommended_stock    - önerilen stok = avg_demand * 1.3 (int | None)
      sample_count         - analiz edilen satış sayısı (int)
      confidence           - "low" | "medium" | "high"
    """
    empty = {
        "suggested_price": None,
        "avg_conversion_rate": None,
        "avg_demand": None,
        "recommended_stock": None,
        "sample_count": 0,
        "confidence": "low",
    }
    ch = await get_clickhouse_client()
    if ch is None:
        return empty

    # listing_id bazlı veya host geneli
    listing_filter = f"AND listing_id = {int(listing_id)}" if listing_id else ""

    sql = f"""
        WITH sales AS (
            SELECT
                sale_id,
                argMaxIf(toFloat64OrNull(toString(viewer_count)), created_at,
                         event_type = 'sale_started')                       AS start_viewers,
                sumIf(toFloat64OrNull(toString(quantity)), event_type = 'purchase_completed')
                                                                            AS total_sold,
                avgIf(toFloat64OrNull(toString(unit_price)), event_type = 'purchase_completed')
                                                                            AS avg_price
            FROM direct_sale_events
            WHERE host_id  = {int(host_id)}
              AND created_at >= now() - INTERVAL {int(lookback_days)} DAY
              {listing_filter}
            GROUP BY sale_id
            HAVING isNotNull(avg_price) AND total_sold > 0
        )
        SELECT
            avg(avg_price)                                                  AS suggested_price,
            avg(if(start_viewers > 0, total_sold / start_viewers, 0))      AS avg_conversion_rate,
            avg(total_sold)                                                 AS avg_demand,
            count()                                                         AS sample_count
        FROM sales
    """
    try:
        result = await ch.query(sql)
        rows = result.result_rows
        if not rows or rows[0][3] == 0:
            # listing bazlı yetersizse host geneline düş
            if listing_id:
                return await get_direct_sale_suggestions(host_id, listing_id=None,
                                                         lookback_days=lookback_days)
            return empty

        suggested_price, avg_cr, avg_demand, sample_count = rows[0]
        sample_count = int(sample_count)
        confidence = "high" if sample_count >= 10 else "medium" if sample_count >= min_samples else "low"
        recommended_stock = max(1, round(float(avg_demand) * 1.3)) if avg_demand else None

        return {
            "suggested_price": round(float(suggested_price), 2) if suggested_price else None,
            "avg_conversion_rate": round(float(avg_cr), 4) if avg_cr else None,
            "avg_demand": round(float(avg_demand), 1) if avg_demand else None,
            "recommended_stock": recommended_stock,
            "sample_count": sample_count,
            "confidence": confidence,
        }
    except Exception as exc:
        logger.warning("[ClickHouse] get_direct_sale_suggestions başarısız: %s", exc)
        return empty
