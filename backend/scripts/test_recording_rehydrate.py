"""Sentetik birim testi — BIZ-01 Bölüm B: 14g PRO Video on-demand rehydrate.

Çalıştır: cd backend && .venv/bin/python3 scripts/test_recording_rehydrate.py

İçerik:
  - rehydrate_from_node2 (başarı, 404→FileNotFoundError, HTTP hata→RuntimeError)
  - get_stream_recording endpoint (available presign, rehydrate, 14g dışı→410, node2'de yok→410, 503)
"""
import sys
import os
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests")
os.environ.setdefault("MINIO_NODE2_REHYDRATE_URL", "http://10.10.0.2:9200")


def _make_user(uid: int = 1, user_type: str = "pro"):
    u = MagicMock()
    u.id = uid
    u.user_type = user_type
    return u


def _make_stream(stream_id: int = 1, host_id: int = 1):
    s = MagicMock()
    s.id = stream_id
    s.host_id = host_id
    return s


def _make_row(
    status: str = "available",
    minio_key: str = "recordings/test.mp4",
    node2_confirmed_at=None,
    created_at: datetime | None = None,
    expires_at: datetime | None = None,
):
    now = datetime.now(timezone.utc)
    row = {
        "id": 42,
        "status": status,
        "minio_key": minio_key,
        "available_at": now - timedelta(hours=1),
        "expires_at": expires_at or (now + timedelta(hours=23)),
        "node2_confirmed_at": node2_confirmed_at,
        "created_at": created_at or (now - timedelta(days=3)),
    }
    return row


class TestRehydrateFromNode2(unittest.IsolatedAsyncioTestCase):
    """rehydrate_from_node2 birim testleri."""

    async def test_success_uploads_to_node1(self):
        """node2'den başarılı indirme → upload_bytes çağrılır, URL döner."""
        from app.services.storage_service import rehydrate_from_node2

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.content_type = "video/mp4"
        mock_resp.read = AsyncMock(return_value=b"fake-video-bytes")

        mock_session_ctx = MagicMock()
        mock_session_ctx.__aenter__ = AsyncMock(return_value=mock_session_ctx)
        mock_session_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_resp_ctx = MagicMock()
        mock_resp_ctx.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_session_ctx.get = MagicMock(return_value=mock_resp_ctx)

        with patch("aiohttp.ClientSession", return_value=mock_session_ctx), \
             patch("app.services.storage_service.upload_bytes", new=AsyncMock(return_value="http://minio1:9010/teqlif/recordings/test.mp4")) as mock_upload:
            result = await rehydrate_from_node2("recordings/test.mp4")

        mock_upload.assert_called_once_with("recordings/test.mp4", b"fake-video-bytes", "video/mp4")
        self.assertEqual(result, "http://minio1:9010/teqlif/recordings/test.mp4")

    async def test_404_raises_file_not_found(self):
        """node2 HTTP 404 → FileNotFoundError."""
        from app.services.storage_service import rehydrate_from_node2

        mock_resp = AsyncMock()
        mock_resp.status = 404

        mock_session_ctx = MagicMock()
        mock_session_ctx.__aenter__ = AsyncMock(return_value=mock_session_ctx)
        mock_session_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_resp_ctx = MagicMock()
        mock_resp_ctx.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_session_ctx.get = MagicMock(return_value=mock_resp_ctx)

        with patch("aiohttp.ClientSession", return_value=mock_session_ctx):
            with self.assertRaises(FileNotFoundError):
                await rehydrate_from_node2("recordings/missing.mp4")

    async def test_http_error_raises_runtime_error(self):
        """node2 HTTP 503 → RuntimeError."""
        from app.services.storage_service import rehydrate_from_node2

        mock_resp = AsyncMock()
        mock_resp.status = 503

        mock_session_ctx = MagicMock()
        mock_session_ctx.__aenter__ = AsyncMock(return_value=mock_session_ctx)
        mock_session_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_resp_ctx = MagicMock()
        mock_resp_ctx.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp_ctx.__aexit__ = AsyncMock(return_value=False)
        mock_session_ctx.get = MagicMock(return_value=mock_resp_ctx)

        with patch("aiohttp.ClientSession", return_value=mock_session_ctx):
            with self.assertRaises(RuntimeError):
                await rehydrate_from_node2("recordings/test.mp4")


class TestGetStreamRecording(unittest.IsolatedAsyncioTestCase):
    """get_stream_recording endpoint birim testleri (BIZ-01 Bölüm B doğrulama)."""

    def _make_db(self, stream=None, row=None):
        db = AsyncMock()
        db.get = AsyncMock(return_value=stream or _make_stream())
        execute_result = MagicMock()
        execute_result.mappings.return_value.first.return_value = row
        db.execute = AsyncMock(return_value=execute_result)
        db.commit = AsyncMock()
        return db

    async def test_available_recording_presigns_directly(self):
        """status=available, expires_at gelecekte → rehydrate atlanır, presign döner."""
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(status="available", expires_at=now + timedelta(hours=23))
        db = self._make_db(row=row)

        with patch("app.services.storage_service._get_presign_client") as mock_client_fn, \
             patch("app.config.settings") as mock_settings, \
             patch("app.services.storage_service.rehydrate_from_node2", new=AsyncMock()) as mock_rehydrate:
            mock_settings.minio_bucket = "teqlif"
            mock_client_fn.return_value.presigned_get_object = MagicMock(return_value="https://presigned.url/rec")

            result = await get_stream_recording(
                stream_id=1, db=db, current_user=_make_user()
            )

        mock_rehydrate.assert_not_called()
        self.assertEqual(result["url"], "https://presigned.url/rec")
        self.assertEqual(result["recording_id"], 42)

    async def test_archived_within_14d_rehydrates(self):
        """status=archived, node2_confirmed, 3 gün önce → rehydrate çağrılır."""
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="archived",
            node2_confirmed_at=now - timedelta(days=1),
            created_at=now - timedelta(days=3),
        )
        db = self._make_db(row=row)

        with patch("app.services.storage_service._get_presign_client") as mock_client_fn, \
             patch("app.config.settings") as mock_settings, \
             patch("app.services.storage_service.rehydrate_from_node2", new=AsyncMock(return_value="http://node1/url")) as mock_rehydrate:
            mock_settings.minio_bucket = "teqlif"
            mock_client_fn.return_value.presigned_get_object = MagicMock(return_value="https://presigned.url/rehydrated")

            result = await get_stream_recording(
                stream_id=1, db=db, current_user=_make_user()
            )

        mock_rehydrate.assert_called_once_with("recordings/test.mp4")
        db.commit.assert_called_once()
        self.assertEqual(result["url"], "https://presigned.url/rehydrated")

    async def test_archived_beyond_14d_returns_410(self):
        """status=archived, 15 gün önce → 410 RECORDING_EXPIRED."""
        from fastapi import HTTPException
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="archived",
            node2_confirmed_at=now - timedelta(days=14),
            created_at=now - timedelta(days=15),
        )
        db = self._make_db(row=row)

        with self.assertRaises(HTTPException) as ctx:
            await get_stream_recording(stream_id=1, db=db, current_user=_make_user())

        self.assertEqual(ctx.exception.status_code, 410)
        self.assertEqual(ctx.exception.detail["error"]["code"], "RECORDING_EXPIRED")

    async def test_archived_no_node2_confirmation_returns_410(self):
        """status=archived, node2_confirmed_at=None → rehydrate edilemez → 410."""
        from fastapi import HTTPException
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="archived",
            node2_confirmed_at=None,
            created_at=now - timedelta(days=3),
        )
        db = self._make_db(row=row)

        with self.assertRaises(HTTPException) as ctx:
            await get_stream_recording(stream_id=1, db=db, current_user=_make_user())

        self.assertEqual(ctx.exception.status_code, 410)

    async def test_rehydrate_node2_missing_returns_410(self):
        """rehydrate_from_node2 FileNotFoundError → 410 RECORDING_EXPIRED."""
        from fastapi import HTTPException
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="archived",
            node2_confirmed_at=now - timedelta(days=1),
            created_at=now - timedelta(days=3),
        )
        db = self._make_db(row=row)

        with patch("app.services.storage_service.rehydrate_from_node2",
                   new=AsyncMock(side_effect=FileNotFoundError("kayıt yok"))):
            with self.assertRaises(HTTPException) as ctx:
                await get_stream_recording(stream_id=1, db=db, current_user=_make_user())

        self.assertEqual(ctx.exception.status_code, 410)

    async def test_rehydrate_network_error_returns_503(self):
        """rehydrate_from_node2 RuntimeError → 503 REHYDRATE_FAILED."""
        from fastapi import HTTPException
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="archived",
            node2_confirmed_at=now - timedelta(days=1),
            created_at=now - timedelta(days=3),
        )
        db = self._make_db(row=row)

        with patch("app.services.storage_service.rehydrate_from_node2",
                   new=AsyncMock(side_effect=RuntimeError("HTTP 503"))):
            with self.assertRaises(HTTPException) as ctx:
                await get_stream_recording(stream_id=1, db=db, current_user=_make_user())

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertEqual(ctx.exception.detail["error"]["code"], "REHYDRATE_FAILED")

    async def test_expired_within_14d_with_node2_rehydrates(self):
        """status=expired, node2_confirmed, 5 gün önce → rehydrate edilir."""
        from app.routers.streams import get_stream_recording

        now = datetime.now(timezone.utc)
        row = _make_row(
            status="expired",
            node2_confirmed_at=now - timedelta(days=2),
            created_at=now - timedelta(days=5),
            expires_at=now - timedelta(hours=1),
        )
        db = self._make_db(row=row)

        with patch("app.services.storage_service._get_presign_client") as mock_client_fn, \
             patch("app.config.settings") as mock_settings, \
             patch("app.services.storage_service.rehydrate_from_node2", new=AsyncMock(return_value="http://node1/url")) as mock_rehydrate:
            mock_settings.minio_bucket = "teqlif"
            mock_client_fn.return_value.presigned_get_object = MagicMock(return_value="https://presigned.url/expired")

            result = await get_stream_recording(
                stream_id=1, db=db, current_user=_make_user()
            )

        mock_rehydrate.assert_called_once()
        self.assertIn("url", result)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestRehydrateFromNode2)
    suite.addTests(loader.loadTestsFromTestCase(TestGetStreamRecording))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
