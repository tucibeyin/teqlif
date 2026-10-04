"""teqlif-agent — Platform Kontrol Düzlemi.

Her node'da çalışır. Gossip, lider seçimi, modüller.
Servis keşfi: hangi systemd servisleri aktifse o modüller yüklenir.
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

__version__ = "1.1.0"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("teqlif-agent")

# Servis adı → yüklenecek recording modülleri
_RECORDING_SERVICES = [
    "teqlif-livekit",
    "teqlif-livekit-staging",
]


async def _active_recording_services() -> list[str]:
    """Bu node'da aktif olan recording servislerini döner."""
    found: list[str] = []
    for svc in _RECORDING_SERVICES:
        try:
            proc = await asyncio.create_subprocess_exec(
                "systemctl", "is-active", "--quiet", svc,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            if proc.returncode == 0:
                found.append(svc)
        except Exception:
            pass
    return found


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

    # Servis bazlı recording modülü keşfi
    rec_services = await _active_recording_services()
    if rec_services:
        from modules.recorder import RecordingManager
        from modules.encoder import EncoderManager
        for svc in rec_services:
            modules.append(RecordingManager(cfg, db, svc))
            modules.append(EncoderManager(cfg, db, svc))
            logger.info("Recording modülleri yüklendi: %s", svc)

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
        tg.create_task(g_srv.serve(stop), name="gossip-server")
        tg.create_task(run_cycles(),      name="main-cycle")


if __name__ == "__main__":
    asyncio.run(main())
