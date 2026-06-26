"""
ClickHouse bağlantı katmanı — bare-metal, Docker yok.

Singleton pattern: uygulama ömrü boyunca tek bir AsyncClient örneği tutulur.
Startup'ta init_clickhouse() çağrılır; tablo yoksa oluşturulur.

Graceful degradation: ClickHouse kapalıysa sadece uyarı loglanır,
PostgreSQL akışı kesintisiz devam eder.
"""

import logging
from typing import Optional

import clickhouse_connect
from clickhouse_connect.driver.asyncclient import AsyncClient

logger = logging.getLogger(__name__)

# ── Singleton ─────────────────────────────────────────────────────────────────

_client: Optional[AsyncClient] = None

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
    timestamp        DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, item_id)
SETTINGS index_granularity = 8192
"""

_CREATE_FEED_ANALYTICS_TABLE = """
CREATE TABLE IF NOT EXISTS feed_analytics
(
    timestamp        DateTime,
    user_id          String,
    listing_id       String,
    event_type       LowCardinality(String),
    dwell_time_ms    UInt32,
    content_type     LowCardinality(String) DEFAULT '',
    slot_index       UInt32 DEFAULT 0,
    stream_category  LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (listing_id, event_type, timestamp)
"""

_ALTER_FEED_ANALYTICS = [
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS content_type LowCardinality(String) DEFAULT ''",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS slot_index UInt32 DEFAULT 0",
    "ALTER TABLE feed_analytics ADD COLUMN IF NOT EXISTS stream_category LowCardinality(String) DEFAULT ''",
]

_CREATE_SEARCH_EVENTS_TABLE = """
CREATE TABLE IF NOT EXISTS search_events
(
    timestamp    DateTime,
    user_id      Nullable(UInt32),
    query        String,
    category     LowCardinality(String) DEFAULT '',
    result_count UInt32 DEFAULT 0
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (category, timestamp)
"""


# ── Public API ────────────────────────────────────────────────────────────────

async def get_clickhouse_client() -> AsyncClient:
    """
    Singleton ClickHouse async istemcisini döndürür.
    İlk çağrıda bağlantıyı kurar (localhost:8123, HTTP arayüzü).
    """
    global _client
    if _client is None:
        _client = await clickhouse_connect.get_async_client(
            host="localhost",
            port=8123,
            connect_timeout=5,
            send_receive_timeout=30,
        )
    return _client


async def init_clickhouse() -> None:
    """
    Uygulama başlangıcında çağrılır:
      1. Bağlantıyı test eder
      2. user_events tablosunu (yoksa) oluşturur
    ClickHouse erişilemezse uyarı loglar, uygulamayı durdurmaz.
    """
    global _client
    try:
        _client = await clickhouse_connect.get_async_client(
            host="localhost",
            port=8123,
            connect_timeout=5,
            send_receive_timeout=30,
        )
        await _client.command(_CREATE_USER_EVENTS_TABLE)
        await _client.command(_CREATE_FEED_ANALYTICS_TABLE)
        for stmt in _ALTER_FEED_ANALYTICS:
            await _client.command(stmt)
        await _client.command(_CREATE_SEARCH_EVENTS_TABLE)
        logger.info("[ClickHouse] Bağlantı kuruldu, tablolar hazır.")
    except Exception as exc:
        logger.warning(
            "[ClickHouse] Başlatma başarısız — servis kapalı olabilir. "
            "PostgreSQL akışı etkilenmez. Hata: %s",
            exc,
        )
        _client = None


async def close_clickhouse() -> None:
    """Uygulama kapanırken bağlantıyı temizler."""
    global _client
    if _client is not None:
        await _client.close()
        _client = None
        logger.info("[ClickHouse] Bağlantı kapatıldı.")


async def track_user_event(
    *,
    event_type: str,
    item_id: int,
    item_type: str,
    user_id: Optional[int] = None,
    price_point: Optional[float] = None,
    duration_seconds: Optional[float] = None,
) -> None:
    """
    user_events tablosuna tek satır ekler. Fire-and-forget — hata olursa sadece loglanır.
    Çağıranı bloklamaz; asyncio.create_task ile çağırılmalıdır.
    """
    if _client is None:
        return
    try:
        await _client.insert(
            "user_events",
            [[user_id, item_id, item_type, event_type, price_point, duration_seconds]],
            column_names=["user_id", "item_id", "item_type", "event_type", "price_point", "duration_seconds"],
        )
    except Exception as exc:
        logger.warning("[ClickHouse] track_user_event başarısız | event=%s item_id=%s | %s", event_type, item_id, exc)
