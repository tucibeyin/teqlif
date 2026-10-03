"""teqlif-agent — Self-Healer.

systemd servislerini izler:
  - ActiveState = failed + restart sayısı burst sınırını aştıysa
    → systemctl reset-failed + systemctl start
  - Her eylemde Telegram bildirir
  - Aynı servis için 10 dk cooldown (sonsuz döngü önlemi)
"""
from __future__ import annotations

import asyncio
import logging
import time

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.healer")

_HEAL_COOLDOWN = 10 * 60   # saniye

# teqlif ve bağımlı servislerin öncelik sırası
_SERVICES_TO_WATCH = [
    "teqlif-app",
    "teqlif-worker-default",
    "teqlif-worker-critical",
    "teqlif-ai-proxy",
    "livekit",
    "postgresql",
    "redis-server",
    "minio",
    "clickhouse-server",
    "haproxy",
    "stalwart-mail",
]


class SelfHealer:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg      = cfg
        self._db       = db
        self._healed: dict[str, float] = {}  # svc → last_heal monotonic

    async def run(self, is_leader: bool) -> None:
        # Her node kendi servislerini iyileştirir — lider olmak gerekmez
        for svc in _SERVICES_TO_WATCH:
            await self._check_and_heal(svc)

    async def _check_and_heal(self, svc: str) -> None:
        state = await _get_active_state(svc)
        if state is None:
            return  # servis bu node'da yok

        if state != "failed":
            return

        now = time.monotonic()
        if now - self._healed.get(svc, 0) < _HEAL_COOLDOWN:
            return

        # StartLimitBurst kontrolü
        burst_exceeded = await _start_limit_exceeded(svc)
        if burst_exceeded:
            ok = await _run("systemctl", "reset-failed", svc)
            logger.info("reset-failed: %s → %s", svc, "OK" if ok else "FAIL")

        ok = await _run("systemctl", "start", svc)
        self._healed[svc] = now

        status = "✅ kurtarıldı" if ok else "❌ başlatılamadı"
        msg = (
            f"🔄 <b>{self._cfg.node_id}</b> — {svc} otomatik {status}\n"
            f"<code>reset-failed={'evet' if burst_exceeded else 'hayır'}</code>"
        )
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, msg)
        logger.warning("SelfHealer: %s — %s", svc, status)

        await self._db.log_cleanup(
            "self_healer", svc, "systemctl_restart",
            "ok" if ok else "failed", self._cfg.node_id,
        )


async def _get_active_state(svc: str) -> str | None:
    try:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "show", svc, "--property=ActiveState",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await proc.communicate()
        line = out.decode().strip()
        if not line or "not-found" in line:
            return None
        return line.split("=", 1)[-1].strip()
    except Exception:
        return None


async def _start_limit_exceeded(svc: str) -> bool:
    try:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "show", svc,
            "--property=NRestarts,ActiveEnterTimestamp",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await proc.communicate()
        for line in out.decode().splitlines():
            if line.startswith("NRestarts="):
                n = int(line.split("=", 1)[-1])
                return n >= 5   # varsayılan StartLimitBurst=5
        return False
    except Exception:
        return False


async def _run(*cmd: str) -> bool:
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
        return proc.returncode == 0
    except Exception:
        return False
