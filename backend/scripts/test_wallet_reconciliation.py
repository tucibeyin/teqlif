"""Sentetik birim testi — daily_financial_reconciliation_task 3-kova formülü.

Çalıştır: python backend/scripts/test_wallet_reconciliation.py

SQLAlchemy / DB bağlantısı gerektirmez — AsyncSession ve Redis mock'lanır.
"""
import sys
import os
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# app.database import sırasında engine oluşturur — test için gerçek URL gerekmiyor
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests")

from app.tasks.wallet_tasks import daily_financial_reconciliation_task


def _make_session_mock(query_results: list):
    """Sıralı execute() çağrılarına karşılık verilen mock session döner.

    query_results: her execute() çağrısı için döndürülecek değerler listesi.
      - fetchall() çağrılan sorgu: liste döner (örn. [] veya [(user_id, avail, pending)])
      - fetchone() çağrılan sorgu: tek satır döner (örn. (100,))
    """
    session = AsyncMock()
    side_effects = []

    for result in query_results:
        result_mock = MagicMock()
        if isinstance(result, list):
            result_mock.fetchall.return_value = result
        else:
            result_mock.fetchone.return_value = result
        side_effects.append(result_mock)

    session.execute = AsyncMock(side_effect=side_effects)

    ctx_mgr = AsyncMock()
    ctx_mgr.__aenter__ = AsyncMock(return_value=session)
    ctx_mgr.__aexit__ = AsyncMock(return_value=False)
    return ctx_mgr


def _make_ctx():
    redis = AsyncMock()
    redis.hset = AsyncMock()
    redis.hdel = AsyncMock()
    return {"redis": redis}


class TestReconciliation(unittest.IsolatedAsyncioTestCase):

    # --- execute çağrı sırası (wallet_tasks.py:124-230) ---
    # 0: neg_rows       → fetchall
    # 1: pending_sum     → fetchone (pending toplamı)
    # 2: gift_pending    → fetchone (gift_events pending toplamı)
    # 3: wr_net          → fetchone (withdrawal_requests net)
    # 4: ledger_withdrawal → fetchone (ledger withdrawal net)
    # 5: avail_sum       → fetchone (available toplamı)
    # 6: earnings_withdrawal_net → fetchone
    # 7: convert_net     → fetchone

    def _clean_queries(
        self, pending=0, gift_pending=0,
        wr_net=0, ledger_withdrawal=0,
        avail=0, earn_wd_net=0, convert_net=0,
    ):
        return [
            [],                    # neg_rows — boş
            (pending,),            # pending_sum
            (gift_pending,),       # gift_pending
            (wr_net,),             # wr_net
            (ledger_withdrawal,),  # ledger_withdrawal
            (avail,),              # avail_sum
            (earn_wd_net,),        # earnings_withdrawal_net
            (convert_net,),        # convert_net
        ]

    async def test_tum_kovalar_esit_anomali_yok(self):
        """Tüm kovalar dengeli → anomali=0, _agent_ok çağrılır."""
        queries = self._clean_queries(
            pending=5000, gift_pending=5000,
            wr_net=1000, ledger_withdrawal=1000,
            avail=8000, earn_wd_net=9000, convert_net=1000,  # 9000-1000=8000
        )
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message") as mock_sentry:
            await daily_financial_reconciliation_task(ctx)

        mock_tg.assert_not_called()
        mock_sentry.assert_not_called()
        ctx["redis"].hset.assert_awaited()   # _agent_ok çağrıldı
        hset_args = ctx["redis"].hset.await_args_list
        assert any("job_ok" in str(a) for a in hset_args), "job_ok yazılmamış"
        ctx["redis"].hdel.assert_awaited()   # fail bayrağı temizlendi

    async def test_kova1_pending_tutarsiz(self):
        """Kova 1: wallet.pending ≠ gift_events.pending → anomali."""
        queries = self._clean_queries(
            pending=5000, gift_pending=4000,  # 1000 fark
            wr_net=0, ledger_withdrawal=0,
            avail=0, earn_wd_net=0, convert_net=0,
        )
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message") as mock_sentry:
            await daily_financial_reconciliation_task(ctx)

        mock_tg.assert_awaited_once()
        mock_sentry.assert_called_once()
        hset_args = ctx["redis"].hset.await_args_list
        assert any("job_fail" in str(a) for a in hset_args), "job_fail yazılmamış"

    async def test_kova2_withdrawal_tutarsiz(self):
        """Kova 2: withdrawal_requests net ≠ ledger net → anomali."""
        queries = self._clean_queries(
            pending=0, gift_pending=0,
            wr_net=2000, ledger_withdrawal=1800,  # 200 fark
            avail=0, earn_wd_net=0, convert_net=0,
        )
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message"):
            await daily_financial_reconciliation_task(ctx)

        mock_tg.assert_awaited_once()

    async def test_kova3_available_tutarsiz(self):
        """Kova 3: available ≠ earnings/withdrawal net − convert_net → anomali."""
        queries = self._clean_queries(
            pending=0, gift_pending=0,
            wr_net=0, ledger_withdrawal=0,
            avail=7500, earn_wd_net=9000, convert_net=1000,  # beklenen=8000, gerçek=7500
        )
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message"):
            await daily_financial_reconciliation_task(ctx)

        mock_tg.assert_awaited_once()

    async def test_negatif_bakiye_anomali(self):
        """Negatif available/pending → anomali."""
        queries = [
            [(42, -100, 0)],   # neg_rows — kullanıcı 42'nin available'ı negatif
            (0,),              # pending_sum
            (0,),              # gift_pending
            (0,),              # wr_net
            (0,),              # ledger_withdrawal
            (0,),              # avail_sum
            (0,),              # earnings_withdrawal_net
            (0,),              # convert_net
        ]
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message"):
            await daily_financial_reconciliation_task(ctx)

        mock_tg.assert_awaited_once()

    async def test_coklu_anomali_tek_telegram(self):
        """2 kova tutarsız → tek Telegram + fail_count=2."""
        queries = self._clean_queries(
            pending=5000, gift_pending=4000,   # Kova 1 bozuk
            wr_net=1000, ledger_withdrawal=800,  # Kova 2 bozuk
            avail=0, earn_wd_net=0, convert_net=0,
        )
        ctx = _make_ctx()
        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=_make_session_mock(queries)), \
             patch("app.tasks.wallet_tasks.send_telegram_alert", new_callable=AsyncMock) as mock_tg, \
             patch("app.tasks.wallet_tasks.capture_message"):
            await daily_financial_reconciliation_task(ctx)

        # Tek send_telegram_alert çağrısı (tüm anomaliler bir mesajda)
        mock_tg.assert_awaited_once()
        call_kwargs = mock_tg.await_args_list[0]
        summary_text = call_kwargs.args[0] if call_kwargs.args else ""
        assert "Anomali sayısı: 2" in summary_text, f"Beklenen 2 anomali: {summary_text}"

    async def test_exception_agent_fail_cagrilir(self):
        """DB exception → _agent_fail çağrılmalı."""
        ctx = _make_ctx()
        failing_session = AsyncMock()
        failing_session.execute = AsyncMock(side_effect=RuntimeError("DB bağlantı hatası"))
        ctx_mgr = AsyncMock()
        ctx_mgr.__aenter__ = AsyncMock(return_value=failing_session)
        ctx_mgr.__aexit__ = AsyncMock(return_value=False)

        with patch("app.tasks.wallet_tasks.AsyncSessionLocal", return_value=ctx_mgr), \
             patch("app.tasks.wallet_tasks.capture_exception"), \
             self.assertRaises(RuntimeError):
            await daily_financial_reconciliation_task(ctx)

        hset_args = ctx["redis"].hset.await_args_list
        assert any("job_fail" in str(a) for a in hset_args), "Exception sonrası job_fail yazılmamış"


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite  = loader.loadTestsFromTestCase(TestReconciliation)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
