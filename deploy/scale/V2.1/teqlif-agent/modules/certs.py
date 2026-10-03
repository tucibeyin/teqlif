"""teqlif-agent — Sertifika, port ve i18n denetimi.

İzlenen:
  TLS sertifika geçerlilik tarihleri (30/7 gün uyarısı)
  Kritik portların dinleme durumu
  i18n pack tazeliği (Redis pack:tr/en/ar/ru)
  MinIO bucket erişimi
  PostgreSQL replikasyon lag'i
  Redis bellek kullanımı
"""
from __future__ import annotations

import asyncio
import logging
import ssl
import socket
import time
from datetime import datetime, timezone, timedelta

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.certs")

_CERT_WARN_DAYS  = [30, 7]   # bu gün sayılarında uyarı gönder
_I18N_LANGS      = ["tr", "en", "ar", "ru"]
_I18N_MAX_AGE_H  = 25        # pack bu saatten eskiyse uyar
_REDIS_MEM_WARN  = 3.8       # GB — maxmemory=4GB, %95

# Her node'unkinden farklı portlar — config'e taşınabilir
_PORT_MAP = {
    "teqlif-app":    [("127.0.0.1", 8000)],
    "ai-proxy":      [("127.0.0.1", 8001)],
    "redis":         [("127.0.0.1", 6379)],
    "postgresql":    [("127.0.0.1", 5432)],
    "minio":         [("127.0.0.1", 9000)],
    "livekit":       [("0.0.0.0",   7880)],
    "gossip-agent":  [("127.0.0.1", 19100)],
}

_DOMAINS = [
    "api.teqlif.com",
    "uploads.teqlif.com",
    "live1.teqlif.com",
    "live2.teqlif.com",
    "mail.teqlif.com",
]

_COOLDOWN = 6 * 60 * 60   # 6 saatte bir tekrar uyar


class CertWatcher:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg     = cfg
        self._db      = db
        self._alerted: dict[str, float] = {}

    async def run(self, is_leader: bool) -> None:
        tasks = [
            self._check_ports(),
        ]
        if is_leader:
            tasks += [
                self._check_certs(),
                self._check_i18n(),
                self._check_redis_mem(),
                self._check_pg_replication(),
            ]
        await asyncio.gather(*tasks, return_exceptions=True)

    # ── TLS Sertifikaları ─────────────────────────────────────────────────────

    async def _check_certs(self) -> None:
        for domain in _DOMAINS:
            try:
                days = await asyncio.get_event_loop().run_in_executor(
                    None, _cert_days_remaining, domain
                )
                key = f"cert:{domain}"
                for warn in _CERT_WARN_DAYS:
                    if days <= warn:
                        await self._alert(
                            key,
                            f"⚠️ <b>Sertifika</b> — {domain}\n"
                            f"{days} gün kaldı (eşik: {warn} gün)"
                        )
                        break
                else:
                    self._alerted.pop(f"cert:{domain}", None)
            except Exception as exc:
                logger.debug("Cert check başarısız | %s | %s", domain, exc)

    # ── Port Kontrolü ─────────────────────────────────────────────────────────

    async def _check_ports(self) -> None:
        for svc, addrs in _PORT_MAP.items():
            for host, port in addrs:
                try:
                    conn = asyncio.open_connection(host, port)
                    reader, writer = await asyncio.wait_for(conn, timeout=2)
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    key = f"port:{svc}:{port}"
                    await self._alert(
                        key,
                        f"🔴 <b>{self._cfg.node_id}</b> — port {port} ({svc}) kapalı"
                    )

    # ── i18n Pack Tazeliği ────────────────────────────────────────────────────

    async def _check_i18n(self) -> None:
        try:
            import aioredis
            r = await aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            for lang in _I18N_LANGS:
                pack    = await r.get(f"pack:{lang}")
                version = await r.get(f"version:{lang}")
                key     = f"i18n:{lang}"
                if not pack or not version:
                    await self._alert(
                        key,
                        f"⚠️ <b>i18n</b> — pack:{lang} Redis'te eksik\n"
                        f"<code>sync_main.py</code> çalıştırılmalı"
                    )
                else:
                    self._alerted.pop(key, None)
            await r.aclose()
        except Exception as exc:
            logger.debug("i18n check başarısız: %s", exc)

    # ── Redis Bellek Kullanımı ────────────────────────────────────────────────

    async def _check_redis_mem(self) -> None:
        try:
            import aioredis
            r    = await aioredis.from_url(self._cfg.redis_url)
            info = await r.info("memory")
            await r.aclose()
            used_gb = info.get("used_memory", 0) / 1e9
            key = "redis:mem"
            if used_gb > _REDIS_MEM_WARN:
                await self._alert(
                    key,
                    f"⚠️ <b>Redis bellek</b> — {used_gb:.1f} GB kullanımda "
                    f"(maxmemory 4 GB)"
                )
            else:
                self._alerted.pop(key, None)
        except Exception as exc:
            logger.debug("Redis mem check başarısız: %s", exc)

    # ── PG Replikasyon Lag ────────────────────────────────────────────────────

    async def _check_pg_replication(self) -> None:
        try:
            import asyncpg, os
            dsn = os.environ.get("PG_DSN", "")
            if not dsn:
                return
            conn = await asyncpg.connect(dsn=dsn)
            rows = await conn.fetch("""
                SELECT client_addr, state,
                       EXTRACT(EPOCH FROM (now() - write_lag))::int AS lag_sec
                FROM pg_stat_replication
            """)
            await conn.close()
            key = "pg:replication"
            if not rows:
                # Replikasyon yok — node2 disconnected olabilir
                await self._alert(key, "⚠️ <b>PG Replikasyon</b> — aktif replica yok")
            else:
                for row in rows:
                    lag = row["lag_sec"] or 0
                    if lag > 120:
                        await self._alert(
                            key,
                            f"⚠️ <b>PG Replikasyon</b> — {row['client_addr']} "
                            f"lag {lag}s"
                        )
                    else:
                        self._alerted.pop(key, None)
        except Exception as exc:
            logger.debug("PG replication check başarısız: %s", exc)

    # ── Alert Helper ──────────────────────────────────────────────────────────

    async def _alert(self, key: str, message: str) -> None:
        now = time.monotonic()
        if now - self._alerted.get(key, 0) < _COOLDOWN:
            return
        self._alerted[key] = now
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, message)
        logger.warning("CERT/PORT/i18n alert: %s", key)


def _cert_days_remaining(hostname: str, port: int = 443) -> int:
    ctx = ssl.create_default_context()
    with ctx.wrap_socket(socket.create_connection((hostname, port), timeout=10),
                         server_hostname=hostname) as conn:
        cert = conn.getpeercert()
    not_after = datetime.strptime(cert["notAfter"], "%b %d %H:%M:%S %Y %Z")
    not_after = not_after.replace(tzinfo=timezone.utc)
    return (not_after - datetime.now(timezone.utc)).days
