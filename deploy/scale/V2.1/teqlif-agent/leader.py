"""teqlif-agent — Deterministik lider seçimi.

Algoritma: WireGuard mesh üzerinden HTTP ping.
"Benden daha yüksek öncelikli (küçük priority numarası) canlı peer var mı?"
  Hayır → benim.
  Evet  → bekle.

Split-brain koruması: tek başarısız ping yeterli değil; üst-öncelikli peer'ların
3 ardışık cycle (3 × cycle_interval) boyunca erişilememesi gerekir.
Geçici ağ titremelerinde (jitter / packet-loss) liderlik el değiştirmez.
"""
from __future__ import annotations

import asyncio
import logging
import time

import aiohttp

from config import AgentConfig, PeerConfig

logger = logging.getLogger("teqlif-agent.leader")

_PING_PATH = "/ping"


_PROMOTE_THRESHOLD = 3  # ardışık başarısız cycle sayısı


class LeaderElector:
    def __init__(self, cfg: AgentConfig) -> None:
        self._cfg       = cfg
        self._is_leader = False
        self._became_leader_at: float | None = None
        self._consecutive_failures: int = 0

    @property
    def is_leader(self) -> bool:
        return self._is_leader

    async def check(self) -> bool:
        higher = self._cfg.higher_priority_peers
        if not higher:
            # En yüksek öncelikli node — her zaman lider, sayaç sıfırla
            self._consecutive_failures = 0
            self._promote()
            return True

        results = await asyncio.gather(
            *[self._ping(p) for p in higher], return_exceptions=True
        )
        any_alive = any(r is True for r in results)

        if any_alive:
            self._consecutive_failures = 0
            self._demote()
            return False

        # Üst-öncelikli tüm peer'lar erişilemez
        self._consecutive_failures += 1
        if self._consecutive_failures >= _PROMOTE_THRESHOLD:
            self._promote()
            return True

        # Sayaç eşiğe ulaşmadı — geçici kesinti olabilir, mevcut durumu koru
        logger.warning(
            "Üst-öncelikli peer'lar erişilemez (%d/%d ardışık) — split-brain koruması aktif",
            self._consecutive_failures,
            _PROMOTE_THRESHOLD,
        )
        return self._is_leader

    async def _ping(self, peer: PeerConfig) -> bool:
        url = f"http://{peer.wg_ip}:{self._cfg.gossip_port}{_PING_PATH}"
        try:
            async with aiohttp.ClientSession() as s:
                async with s.get(
                    url,
                    headers={"Authorization": f"Bearer {self._cfg.gossip_token}"},
                    timeout=aiohttp.ClientTimeout(total=self._cfg.gossip_timeout),
                ) as resp:
                    return resp.status == 200
        except Exception:
            return False

    def _promote(self) -> None:
        if not self._is_leader:
            logger.info("Lider seçildim — %s (priority=%d)", self._cfg.node_id, self._cfg.priority)
            self._is_leader = True
            self._became_leader_at = time.monotonic()

    def _demote(self) -> None:
        if self._is_leader:
            logger.info("Liderliği bıraktım — daha öncelikli peer canlı.")
            self._is_leader = False
            self._became_leader_at = None
