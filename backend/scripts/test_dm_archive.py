"""Sentetik birim testi — BIZ-01 Bölüm A: DM arşiv okuma (private bucket).

Çalıştır: cd backend && .venv/bin/python3 scripts/test_dm_archive.py

İçerik:
  - _list_object_keys_impl (strict/non-strict, 0 node, tüm node hata, union)
  - get_archived_messages endpoint (happy path, listing hatası → 502, bytes hatası → 502)
"""
import sys
import os
import gzip
import json
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests")

from app.services.storage_service import _list_object_keys_impl


def _gzip_payload(messages: list) -> bytes:
    return gzip.compress(json.dumps(messages).encode())


def _make_user(uid: int = 1):
    user = MagicMock()
    user.id = uid
    return user


_SAMPLE_MSGS = [
    {
        "id": 1,
        "sender_id": 1,
        "receiver_id": 2,
        "content": "merhaba",
        "created_at": "2023-06-15T10:00:00+00:00",
    }
]


class TestListObjectKeysImpl(unittest.IsolatedAsyncioTestCase):
    """_list_object_keys_impl strict/non-strict davranış testleri."""

    async def test_strict_no_nodes_raises(self):
        """strict=True, 0 node → RuntimeError."""
        with patch("app.services.storage_service._get_all_storage_clients", new=AsyncMock(return_value=[])):
            with self.assertRaises(RuntimeError):
                await _list_object_keys_impl("teqlif-dm", "dm-archive/1_2/", "TEST_DM", strict=True)

    async def test_non_strict_no_nodes_returns_empty(self):
        """strict=False, 0 node → []."""
        with patch("app.services.storage_service._get_all_storage_clients", new=AsyncMock(return_value=[])):
            result = await _list_object_keys_impl("teqlif", "dm-archive/1_2/", "TEST", strict=False)
            self.assertEqual(result, [])

    async def test_strict_all_nodes_fail_raises_last(self):
        """strict=True, tüm node'lar hata → son exception fırlatılır."""
        err = ConnectionError("MinIO bağlantı koptu")
        c = MagicMock()
        c.list_objects.side_effect = err
        clients = [(c, "node1"), (c, "node2")]
        with patch("app.services.storage_service._get_all_storage_clients", new=AsyncMock(return_value=clients)):
            with self.assertRaises(ConnectionError):
                await _list_object_keys_impl("teqlif-dm", "dm-archive/1_2/", "TEST_DM", strict=True)

    async def test_non_strict_all_nodes_fail_returns_empty(self):
        """strict=False, tüm node'lar hata → [] döner, fırlatmaz."""
        c = MagicMock()
        c.list_objects.side_effect = ConnectionError("hata")
        clients = [(c, "node1")]
        with patch("app.services.storage_service._get_all_storage_clients", new=AsyncMock(return_value=clients)):
            result = await _list_object_keys_impl("teqlif", "dm-archive/1_2/", "TEST", strict=False)
            self.assertEqual(result, [])

    async def test_union_across_nodes(self):
        """Birden fazla node'dan gelen key'ler birleştirilir (set union)."""
        c1 = MagicMock()
        c1.list_objects.return_value = [MagicMock(object_name="dm-archive/1_2/2023.json.gz")]
        c2 = MagicMock()
        c2.list_objects.return_value = [
            MagicMock(object_name="dm-archive/1_2/2023.json.gz"),
            MagicMock(object_name="dm-archive/1_2/2024.json.gz"),
        ]
        with patch("app.services.storage_service._get_all_storage_clients", new=AsyncMock(return_value=[(c1, "node1"), (c2, "node2")])):
            result = await _list_object_keys_impl("teqlif-dm", "dm-archive/1_2/", "TEST_DM", strict=True)
            self.assertEqual(sorted(result), ["dm-archive/1_2/2023.json.gz", "dm-archive/1_2/2024.json.gz"])


class TestGetArchivedMessages(unittest.IsolatedAsyncioTestCase):
    """get_archived_messages endpoint birim testleri (01_findings.md#L977 doğrulama)."""

    async def test_happy_path_returns_messages(self):
        """Normal akış: DM key'ler bulunur, gzip aç → MessageOut listesi döner."""
        from app.routers.messages import get_archived_messages

        raw = _gzip_payload(_SAMPLE_MSGS)
        with patch("app.services.storage_service.list_object_keys_dm", new=AsyncMock(return_value=["dm-archive/1_2/2023.json.gz"])), \
             patch("app.services.storage_service.get_object_bytes_dm", new=AsyncMock(return_value=raw)):
            result = await get_archived_messages(other_user_id=2, current_user=_make_user(1))

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].content, "merhaba")
        self.assertEqual(result[0].sender_id, 1)

    async def test_empty_prefix_returns_empty_list(self):
        """DM yok (boş liste) → [] döner, hata değil."""
        from app.routers.messages import get_archived_messages

        with patch("app.services.storage_service.list_object_keys_dm", new=AsyncMock(return_value=[])):
            result = await get_archived_messages(other_user_id=2, current_user=_make_user(1))
        self.assertEqual(result, [])

    async def test_list_keys_raises_returns_502(self):
        """list_object_keys_dm hata → HTTPException 502."""
        from fastapi import HTTPException
        from app.routers.messages import get_archived_messages

        with patch("app.services.storage_service.list_object_keys_dm", new=AsyncMock(side_effect=RuntimeError("MinIO down"))):
            with self.assertRaises(HTTPException) as ctx:
                await get_archived_messages(other_user_id=2, current_user=_make_user(1))
        self.assertEqual(ctx.exception.status_code, 502)

    async def test_get_bytes_raises_returns_502(self):
        """get_object_bytes_dm ağ hatası → HTTPException 502 (sessiz skip yok)."""
        from fastapi import HTTPException
        from app.routers.messages import get_archived_messages

        with patch("app.services.storage_service.list_object_keys_dm", new=AsyncMock(return_value=["dm-archive/1_2/2023.json.gz"])), \
             patch("app.services.storage_service.get_object_bytes_dm", new=AsyncMock(side_effect=ConnectionError("S3 timeout"))):
            with self.assertRaises(HTTPException) as ctx:
                await get_archived_messages(other_user_id=2, current_user=_make_user(1))
        self.assertEqual(ctx.exception.status_code, 502)

    async def test_user_a_b_ordering(self):
        """user_a = min(uid, other), user_b = max → prefix tutarlı."""
        from app.routers.messages import get_archived_messages

        captured_prefix = []

        async def _mock_list(prefix):
            captured_prefix.append(prefix)
            return []

        with patch("app.services.storage_service.list_object_keys_dm", side_effect=_mock_list):
            await get_archived_messages(other_user_id=5, current_user=_make_user(3))

        self.assertEqual(captured_prefix[0], "dm-archive/3_5/")


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestListObjectKeysImpl)
    suite.addTests(loader.loadTestsFromTestCase(TestGetArchivedMessages))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
