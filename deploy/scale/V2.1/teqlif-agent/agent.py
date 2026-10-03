"""teqlif-agent — Platform Kontrol Düzlemi.

Her node'da çalışır. Gossip, lider seçimi, modüller.
"""
from __future__ import annotations

import asyncio
import logging
import signal
import sys

from config import load_config
from db import AgentDB
from leader import LeaderElector
from gossip import GossipServer, GossipClient
from modules.health import HealthMonitor
from modules.watchdog import JobWatchdog
from modules.janitor import TTLJanitor
from modules.healer import SelfHealer
from modules.certs import CertWatcher
from modules.cleaner import ScheduledCleaner

__version__ = "1.0.0"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("teqlif-agent")


async def main() -> None:
    cfg = load_config()
    logging.getLogger().setLevel(cfg.log_level)
    logger.info("teqlif-agent v%s başlatılıyor | node=%s priority=%d",
                __version__, cfg.node_id, cfg.priority)

    db      = AgentDB(cfg.db_path)
    await db.init()

    elector = LeaderElector(cfg)
    g_srv   = GossipServer(cfg, db)
    g_cli   = GossipClient(cfg, db)

    modules = [
        HealthMonitor(cfg, db),
        JobWatchdog(cfg, db),
        TTLJanitor(cfg, db),
        ScheduledCleaner(cfg, db),
        SelfHealer(cfg, db),
        CertWatcher(cfg, db),
    ]

    # Temiz kapanış
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    async def run_cycles() -> None:
        while not stop.is_set():
            try:
                is_leader = await elector.check()
                if is_leader != getattr(run_cycles, "_was_leader", None):
                    run_cycles._was_leader = is_leader
                    logger.info("Lider durumu: %s", "LİDER" if is_leader else "pasif")

                await g_cli.sync_all()

                for mod in modules:
                    try:
                        await mod.run(is_leader=is_leader)
                    except Exception as exc:
                        logger.error("Modül hatası | %s | %s", mod.__class__.__name__, exc)

            except Exception as exc:
                logger.error("Döngü hatası: %s", exc)

            try:
                await asyncio.wait_for(stop.wait(), timeout=cfg.cycle_interval)
            except asyncio.TimeoutError:
                pass

        await db.close()
        logger.info("teqlif-agent durduruldu.")

    async with asyncio.TaskGroup() as tg:
        tg.create_task(g_srv.serve(), name="gossip-server")
        tg.create_task(run_cycles(),  name="main-cycle")


if __name__ == "__main__":
    asyncio.run(main())
