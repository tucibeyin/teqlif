"""teqlif-agent — Gossip HTTP sunucusu ve senkronizasyon istemcisi."""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone, timedelta

import aiohttp
from aiohttp import web

from config import AgentConfig, PeerConfig
from db import AgentDB

logger = logging.getLogger("teqlif-agent.gossip")

_EPOCH = "1970-01-01T00:00:00+00:00"


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
        app.router.add_get("/ping",  self._handle_ping)
        app.router.add_get("/delta", self._handle_delta)
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, self._cfg.wg_ip, self._cfg.gossip_port)
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


class GossipClient:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg        = cfg
        self._db         = db
        self._last_sync: dict[str, str] = {}   # node_id → son sync timestamp

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
        self._last_sync[peer.node_id] = datetime.now(timezone.utc).isoformat()
        logger.debug("Gossip sync OK | peer=%s", peer.node_id)
