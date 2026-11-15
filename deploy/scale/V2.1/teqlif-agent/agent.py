"""teqlif-agent — Platform Kontrol Düzlemi.

Her node'da çalışır. Gossip, lider seçimi, modüller.
Servis keşfi: hangi systemd servisleri aktifse o modüller yüklenir.
"""
from __future__ import annotations

import asyncio
import logging
import signal
import sys

from alerter import TelegramBot
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
from modules.reporter import MorningReporter, StagingMorningReporter
from modules.commander import TelegramCommander

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
    await g_cli.load_sync_state()

    prod_bot     = TelegramBot(cfg.telegram_bot_token)
    prod_alerter = prod_bot.alerter(cfg.telegram_chat_id)

    _staging_token  = cfg.staging_telegram_bot_token or cfg.telegram_bot_token
    staging_bot     = TelegramBot(_staging_token)
    staging_alerter = (
        staging_bot.alerter(cfg.staging_telegram_chat_id)
        if cfg.staging_telegram_chat_id
        else None
    )

    modules = [
        HealthMonitor(cfg, db, prod_alerter, staging_alerter),
        JobWatchdog(cfg, db, prod_alerter),
        TTLJanitor(cfg, db),
        ScheduledCleaner(cfg, db, prod_alerter),
        SelfHealer(cfg, db, prod_alerter),
        CertWatcher(cfg, db, prod_alerter),
        MorningReporter(cfg, db, prod_alerter),
        StagingMorningReporter(cfg, staging_alerter or prod_alerter),
        TelegramCommander(db, prod_bot, prod_alerter, staging_bot, staging_alerter, restart_gw=g_cli),
    ]

    # Servis bazlı recording + relay modülü keşfi
    rec_services = await _active_recording_services()
    if rec_services:
        from modules.recorder import RecordingManager
        from modules.encoder import EncoderManager
        from modules.relay import RelayManager
        for svc in rec_services:
            rec_mgr   = RecordingManager(cfg, db, svc)
            enc_mgr   = EncoderManager(cfg, db, svc, recording_procs=rec_mgr._procs)
            relay_mgr = RelayManager(cfg, db, svc)
            modules.append(rec_mgr)
            modules.append(enc_mgr)
            modules.append(relay_mgr)
            logger.info("Recording + Relay modülleri yüklendi: %s", svc)

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
