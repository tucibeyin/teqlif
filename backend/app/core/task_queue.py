"""
ARQ task queue — global pool yönetimi.

request.app.state'e erişimi olmayan utility fonksiyonları
(push_notification gibi) bu modülden pool'a ulaşır.

Kullanım:
    from app.core.task_queue import get_pool

    pool = get_pool()
    if pool:
        await pool.enqueue_job("send_push_notification_task", ...)
"""

from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from arq import ArqRedis

_pool: "ArqRedis | None" = None


def set_pool(pool: "ArqRedis") -> None:
    """lifespan başlangıcında çağrılır."""
    global _pool
    _pool = pool


def get_pool() -> "ArqRedis | None":
    """
    Mevcut ARQ pool'unu döner.
    Henüz başlatılmamışsa None döner — çağıran sessizce fallback uygular.
    """
    return _pool


def clear_pool() -> None:
    """lifespan kapanışında çağrılır."""
    global _pool
    _pool = None
