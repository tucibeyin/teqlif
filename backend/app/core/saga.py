"""
Saga — Dağıtık işlem kompanzasyon çerçevesi.

Tek DB transaction içinde çözülemeyen çok adımlı işlemler için:
her adım kendi işlemini yapar, başarısız olduğunda kompanzasyon
aksiyonları (geri alımlar) ters sırayla çalışır.

Kullanım:
    async with Saga("accept_bid") as saga:
        auction = await saga.step(
            "create_auction",
            do=lambda: _create_auction(db),
            compensate=lambda: db.delete(auction),
        )
        await saga.step(
            "update_listing",
            do=lambda: _deactivate_listing(db, listing),
            compensate=lambda: _reactivate_listing(db, listing),
        )
        await db.commit()   # tek commit noktası
    # İstisna olursa kompanzasyonlar otomatik çalışır
"""
from __future__ import annotations

import asyncio
from typing import Any, Callable, Coroutine

from app.core.logger import get_logger

logger = get_logger(__name__)


class SagaStep:
    def __init__(
        self,
        name: str,
        compensate: Callable[[], Coroutine] | None,
    ):
        self.name = name
        self.compensate = compensate


class SagaError(Exception):
    """Saga adımı başarısız oldu ve kompanzasyonlar çalıştı."""


class Saga:
    """
    name: log ve hata mesajlarında kullanılır
    """

    def __init__(self, name: str):
        self.name = name
        self._steps: list[SagaStep] = []
        self._failed = False

    async def step(
        self,
        step_name: str,
        do: Callable[[], Coroutine],
        compensate: Callable[[], Coroutine] | None = None,
    ) -> Any:
        """
        Bir adım çalıştır, başarısızsa kompanzasyon zincirini tetikle.
        Sonucu döner.
        """
        try:
            result = await do()
            self._steps.append(SagaStep(step_name, compensate))
            logger.debug("[SAGA:%s] adım tamamlandı | %s", self.name, step_name)
            return result
        except Exception as exc:
            logger.error(
                "[SAGA:%s] adım başarısız | %s | %s", self.name, step_name, exc
            )
            self._failed = True
            await self._compensate()
            raise SagaError(
                f"Saga '{self.name}' adım '{step_name}' başarısız: {exc}"
            ) from exc

    async def _compensate(self) -> None:
        """Tamamlanan adımları ters sırayla geri al."""
        for step in reversed(self._steps):
            if step.compensate is None:
                continue
            try:
                await step.compensate()
                logger.info(
                    "[SAGA:%s] kompanzasyon tamamlandı | %s", self.name, step.name
                )
            except Exception as exc:
                logger.error(
                    "[SAGA:%s] kompanzasyon BAŞARISIZ | %s | %s",
                    self.name, step.name, exc,
                )

    async def __aenter__(self) -> "Saga":
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> bool:
        if exc_type is not None and not self._failed:
            # step() dışındaki bir hata (örn. db.commit() başarısız)
            self._failed = True
            await self._compensate()
        return False  # exception'ı yutma
