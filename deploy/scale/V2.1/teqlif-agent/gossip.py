"""teqlif-agent — Gossip HTTP sunucusu ve senkronizasyon istemcisi."""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone, timedelta
from pathlib import Path

import aiohttp
from aiohttp import web

from config import AgentConfig, PeerConfig
from db import AgentDB, _EPOCH
from constants import RESTARTABLE_SVCS, STARTABLE_SVCS

logger = logging.getLogger("teqlif-agent.gossip")


def _auth_middleware(token: str):
    @web.middleware
    async def middleware(request: web.Request, handler):
        auth = request.headers.get("Authorization", "")
        if auth != f"Bearer {token}":
            raise web.HTTPUnauthorized()
        return await handler(request)
    return middleware


class GossipServer:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg = cfg
        self._db  = db

    async def serve(self, stop: asyncio.Event) -> None:
        app = web.Application(middlewares=[_auth_middleware(self._cfg.gossip_token)])
        app.router.add_get("/ping",   self._handle_ping)
        app.router.add_get("/delta",  self._handle_delta)
        app.router.add_post("/cmd",   self._handle_cmd)
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, self._cfg.wg_ip, self._cfg.gossip_port, reuse_address=True)
        await site.start()
        logger.info("Gossip sunucu: %s:%d", self._cfg.wg_ip, self._cfg.gossip_port)
        await stop.wait()
        await runner.cleanup()

    async def _handle_ping(self, request: web.Request) -> web.Response:
        return web.json_response({"node_id": self._cfg.node_id, "ok": True})

    async def _handle_delta(self, request: web.Request) -> web.Response:
        since = request.query.get("since", _EPOCH)
        delta = await self._db.get_delta(since)
        return web.json_response(delta)

    async def _handle_cmd(self, request: web.Request) -> web.Response:
        """Uzak komut işleyici — sadece WireGuard mesh içinden erişilebilir."""
        try:
            data = await request.json()
        except Exception:
            return web.json_response({"ok": False, "error": "invalid JSON"}, status=400)

        handlers = {
            "restart_service": self._cmd_restart_service,
            "start_unit":      self._cmd_start_unit,
            "get_logs":        self._cmd_get_logs,
        }
        cmd = data.get("cmd")
        fn  = handlers.get(cmd)
        if fn is None:
            return web.json_response({"ok": False, "error": f"unknown cmd: {cmd}"}, status=400)
        return await fn(data)

    async def _cmd_restart_service(self, data: dict) -> web.Response:
        svc = str(data.get("service", "")).strip()
        if svc not in RESTARTABLE_SVCS:
            logger.warning("Reddedilen restart isteği: %s", svc)
            return web.json_response({"ok": False, "error": f"not allowed: {svc}"}, status=403)
        if not _unit_exists(svc):
            return web.json_response({"ok": False, "error": f"not on this node: {svc}"}, status=404)
        err = await _busctl_unit("RestartUnit", svc)
        if err:
            return web.json_response({"ok": False, "error": err}, status=500)
        logger.info("Uzak restart: %s", svc)
        return web.json_response({"ok": True, "restarted": svc})

    async def _cmd_start_unit(self, data: dict) -> web.Response:
        svc = str(data.get("service", "")).strip()
        if svc not in STARTABLE_SVCS:
            logger.warning("Reddedilen start isteği: %s", svc)
            return web.json_response({"ok": False, "error": f"not allowed: {svc}"}, status=403)
        if not _unit_exists(svc):
            return web.json_response({"ok": False, "error": f"not on this node: {svc}"}, status=404)
        err = await _busctl_unit("StartUnit", svc)
        if err:
            return web.json_response({"ok": False, "error": err}, status=500)
        logger.info("Uzak start: %s", svc)
        return web.json_response({"ok": True, "started": svc})

    async def _cmd_get_logs(self, data: dict) -> web.Response:
        svc = str(data.get("service", "")).strip()
        n   = min(int(data.get("n", 20)), 50)
        if not _unit_exists(svc):
            return web.json_response({"ok": False, "error": f"not on this node: {svc}"}, status=404)
        try:
            proc = await asyncio.create_subprocess_exec(
                "journalctl", "-u", svc, "-n", str(n), "--no-pager", "--output=short",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
            lines = out.decode(errors="replace").strip()
        except asyncio.TimeoutError:
            return web.json_response({"ok": False, "error": "journalctl timeout"}, status=500)
        except Exception as exc:
            return web.json_response({"ok": False, "error": str(exc)[:100]}, status=500)
        return web.json_response({"ok": True, "lines": lines})


class GossipClient:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg        = cfg
        self._db         = db
        self._last_sync: dict[str, str] = {}   # node_id → son sync timestamp (DB destekli)

    async def load_sync_state(self) -> None:
        """DB'den kalıcı sync state'i yükle — restart sonrası _EPOCH'a dönüşü önler."""
        for peer in self._cfg.peers:
            self._last_sync[peer.node_id] = await self._db.get_last_sync(peer.node_id)
        logger.debug("Gossip sync state yüklendi: %d peer", len(self._last_sync))

    def _resolve_wg_ip(self, node_id: str) -> str | None:
        for peer in self._cfg.peers:
            if peer.node_id == node_id:
                return peer.wg_ip
        return self._cfg.wg_ip if node_id == self._cfg.node_id else None

    async def _post_cmd(self, node_id: str, payload: dict) -> dict:
        wg_ip = self._resolve_wg_ip(node_id)
        if not wg_ip:
            return {"ok": False, "error": f"node bulunamadı: {node_id}"}
        url     = f"http://{wg_ip}:{self._cfg.gossip_port}/cmd"
        headers = {"Authorization": f"Bearer {self._cfg.gossip_token}"}
        try:
            async with aiohttp.ClientSession() as s:
                async with s.post(
                    url, json=payload, headers=headers,
                    timeout=aiohttp.ClientTimeout(total=15),
                ) as r:
                    return await r.json()
        except Exception as exc:
            return {"ok": False, "error": str(exc)[:100]}

    async def restart_service(self, node_id: str, service: str) -> dict:
        """Hedef node'da servis restart isteği gönderir (gossip /cmd)."""
        return await self._post_cmd(node_id, {"cmd": "restart_service", "service": service})

    async def start_unit(self, node_id: str, service: str) -> dict:
        """Hedef node'da one-shot servis başlatır (backup trigger vb.)."""
        return await self._post_cmd(node_id, {"cmd": "start_unit", "service": service})

    async def get_service_logs(self, node_id: str, service: str, n: int = 20) -> dict:
        """Hedef node'dan servis journal loglarını getirir."""
        return await self._post_cmd(node_id, {"cmd": "get_logs", "service": service, "n": n})

    async def sync_all(self) -> None:
        """Tüm erişilebilir peer'larla delta exchange yapar."""
        for peer in self._cfg.peers:
            try:
                await self._sync_peer(peer)
            except Exception as exc:
                logger.debug("Gossip sync başarısız | peer=%s | %s", peer.node_id, exc)

    async def _sync_peer(self, peer: PeerConfig) -> None:
        since = self._last_sync.get(peer.node_id, _EPOCH)
        url   = f"http://{peer.wg_ip}:{self._cfg.gossip_port}/delta?since={since}"
        headers = {"Authorization": f"Bearer {self._cfg.gossip_token}"}

        async with aiohttp.ClientSession() as session:
            async with session.get(
                url, headers=headers,
                timeout=aiohttp.ClientTimeout(total=self._cfg.gossip_timeout),
            ) as resp:
                if resp.status != 200:
                    return
                delta = await resp.json()

        await self._db.apply_delta(delta)
        now = datetime.now(timezone.utc).isoformat()
        self._last_sync[peer.node_id] = now
        await self._db.set_last_sync(peer.node_id, now)
        logger.debug("Gossip sync OK | peer=%s", peer.node_id)


# ── Yardımcı Fonksiyonlar ─────────────────────────────────────────────────────

def _unit_exists(svc: str) -> bool:
    return (
        Path(f"/etc/systemd/system/{svc}.service").exists()
        or Path(f"/lib/systemd/system/{svc}.service").exists()
    )


async def _busctl_unit(action: str, svc: str) -> str | None:
    """busctl ile systemd unit'i başlatır/yeniden başlatır. Hata string'i döner, başarıda None."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "busctl", "--system", "call",
            "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
            "org.freedesktop.systemd1.Manager", action,
            "ss", f"{svc}.service", "fail",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await asyncio.wait_for(proc.communicate(), timeout=10)
        if proc.returncode != 0:
            err = stderr.decode(errors="replace")[:200]
            logger.error("busctl %s başarısız: %s | %s", action, svc, err)
            return err
        return None
    except asyncio.TimeoutError:
        return "busctl timeout"
    except Exception as exc:
        return str(exc)[:100]
