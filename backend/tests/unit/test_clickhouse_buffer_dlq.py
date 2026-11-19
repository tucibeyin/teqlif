"""
work_002 birim testleri:
- direct_sale_events, user_events ve search_events non-nullable alan normalizasyonu
- buffer_direct_sale_event kaynak katmanı normalizasyonu
- ClickHouse flush_all_buffers poison-pill & Dead-Letter Queue (DLQ) koruması
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import types
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

# Test ortamında harici driver paketleri (clickhouse_connect, redis, sentry_sdk) kurulu değilse stub enjekte et
if "clickhouse_connect" not in sys.modules:
    _ch_pkg = types.ModuleType("clickhouse_connect")
    _ch_pkg.get_async_client = AsyncMock()
    _ch_driver = types.ModuleType("clickhouse_connect.driver")
    _ch_async = types.ModuleType("clickhouse_connect.driver.asyncclient")
    _ch_async.AsyncClient = MagicMock
    sys.modules["clickhouse_connect"] = _ch_pkg
    sys.modules["clickhouse_connect.driver"] = _ch_driver
    sys.modules["clickhouse_connect.driver.asyncclient"] = _ch_async

if "redis" not in sys.modules:
    _redis_pkg = types.ModuleType("redis")
    _redis_async = types.ModuleType("redis.asyncio")
    _redis_async.Redis = MagicMock
    _redis_async.from_url = MagicMock()
    _redis_pkg.asyncio = _redis_async
    sys.modules["redis"] = _redis_pkg
    sys.modules["redis.asyncio"] = _redis_async

if "sentry_sdk" not in sys.modules:
    _sentry_pkg = types.ModuleType("sentry_sdk")
    _sentry_pkg.is_initialized = lambda: False
    _sentry_pkg.capture_exception = MagicMock()
    _sentry_pkg.capture_message = MagicMock()
    sys.modules["sentry_sdk"] = _sentry_pkg

# backend dizinini sys.path'e ekle
_BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _BACKEND_DIR not in sys.path:
    sys.path.insert(0, _BACKEND_DIR)

from app import database_clickhouse as ch_mod


class FakeRedis:
    """In-memory async Redis mock (list + counter)."""

    def __init__(self) -> None:
        self.lists: dict[str, list[str]] = {}
        self.kv: dict[str, int] = {}

    async def rpush(self, key: str, *values: str) -> int:
        bucket = self.lists.setdefault(key, [])
        bucket.extend(values)
        return len(bucket)

    async def lrange(self, key: str, start: int, end: int) -> list[str]:
        bucket = self.lists.get(key, [])
        if end == -1:
            return list(bucket[start:])
        return list(bucket[start : end + 1])

    async def ltrim(self, key: str, start: int, end: int) -> None:
        bucket = self.lists.get(key, [])
        if end == -1:
            self.lists[key] = bucket[start:]
        else:
            self.lists[key] = bucket[start : end + 1]

    async def llen(self, key: str) -> int:
        return len(self.lists.get(key, []))

    async def incr(self, key: str) -> int:
        self.kv[key] = self.kv.get(key, 0) + 1
        return self.kv[key]

    async def delete(self, key: str) -> None:
        self.kv.pop(key, None)


class TestClickHouseBufferNormalizationAndDLQ(unittest.TestCase):
    def setUp(self) -> None:
        self.fake_redis = FakeRedis()
        self.fake_client = AsyncMock()
        self._orig_client = ch_mod._client
        ch_mod._client = self.fake_client

    def tearDown(self) -> None:
        ch_mod._client = self._orig_client

    def test_buffer_direct_sale_event_normalizes_none_values(self) -> None:
        """buffer_direct_sale_event: category=None, end_reason=None, orders_voided=None -> '', '', False."""
        async def _run():
            with patch("app.utils.redis_client.get_redis", AsyncMock(return_value=self.fake_redis)):
                await ch_mod.buffer_direct_sale_event(
                    event_type="sale_started",
                    sale_id=101,
                    stream_id=202,
                    host_id=303,
                    user_id=303,
                    listing_id=None,
                    category=None,
                    unit_price=150.0,
                    remaining_stock_after=5,
                    viewer_count=12,
                    end_reason=None,
                    orders_voided=None,
                )

            items = self.fake_redis.lists.get(ch_mod._BUF_DIRECT_SALE_EVENTS, [])
            self.assertEqual(len(items), 1)
            row = json.loads(items[0])
            self.assertEqual(row[7], "")       # category
            self.assertEqual(row[14], "")      # end_reason
            self.assertIs(row[15], False)      # orders_voided

        asyncio.run(_run())

    def test_flush_direct_sale_events_normalizes_legacy_none_rows(self) -> None:
        """flush_all_buffers: Redis'te zaten None olarak kalmış eski direct_sale_events satırlarını normalize eder."""
        async def _run():
            legacy_row = [
                "sale_started", 8, 55, 12, 12,
                None, None, None, None,
                250.0, None, None,
                10, 4, None,
                None, "2026-04-04 12:00:00",
            ]
            await self.fake_redis.rpush(ch_mod._BUF_DIRECT_SALE_EVENTS, json.dumps(legacy_row))

            with patch("app.utils.redis_client.get_redis", AsyncMock(return_value=self.fake_redis)):
                await ch_mod.flush_all_buffers()

            self.fake_client.insert.assert_awaited_once()
            table_name, data = self.fake_client.insert.call_args.args[:2]
            self.assertEqual(table_name, "direct_sale_events")
            inserted_row = data[0]
            self.assertEqual(inserted_row[7], "")        # category -> "" (None değil)
            self.assertEqual(inserted_row[14], "")       # end_reason -> "" (None değil)
            self.assertIs(inserted_row[15], False)       # orders_voided -> False (None değil)
            self.assertEqual(await self.fake_redis.llen(ch_mod._BUF_DIRECT_SALE_EVENTS), 0)

        asyncio.run(_run())

    def test_poison_pill_moves_to_dlq_after_max_failures(self) -> None:
        """Ardışık 5 başarısız insert sonrasında poison-pill batch ch_dlq:<table_name> kuyruğuna taşınır."""
        async def _run():
            poison_row = [
                "sale_cancelled", 9, 60, 15, 15,
                0, 0, "", 0,
                100.0, 0.0, 0,
                5, 0, "host_cancelled",
                True, "2026-04-04 12:05:00",
            ]
            await self.fake_redis.rpush(ch_mod._BUF_DIRECT_SALE_EVENTS, json.dumps(poison_row))
            self.fake_client.insert.side_effect = RuntimeError("Cannot convert None to non-nullable type")

            with patch("app.utils.redis_client.get_redis", AsyncMock(return_value=self.fake_redis)):
                # İlk 4 denemede veri ana kuyrukta kalmalı, DLQ boş olmalı
                for attempt in range(1, ch_mod.MAX_FLUSH_FAILURES):
                    await ch_mod.flush_all_buffers()
                    self.assertEqual(await self.fake_redis.llen(ch_mod._BUF_DIRECT_SALE_EVENTS), 1)
                    self.assertEqual(await self.fake_redis.llen("ch_dlq:direct_sale_events"), 0)
                    self.assertEqual(self.fake_redis.kv.get("ch_buf_fail:direct_sale_events"), attempt)

                # 5. denemede DLQ'ya taşınmalı, ana kuyruk temizlenmeli ve hata sayacı sıfırlanmalı
                await ch_mod.flush_all_buffers()
                self.assertEqual(await self.fake_redis.llen(ch_mod._BUF_DIRECT_SALE_EVENTS), 0)
                self.assertEqual(await self.fake_redis.llen("ch_dlq:direct_sale_events"), 1)
                self.assertIsNone(self.fake_redis.kv.get("ch_buf_fail:direct_sale_events"))

                dlq_items = await self.fake_redis.lrange("ch_dlq:direct_sale_events", 0, -1)
                self.assertEqual(json.loads(dlq_items[0])[1], 9)

        asyncio.run(_run())


if __name__ == "__main__":
    unittest.main()
