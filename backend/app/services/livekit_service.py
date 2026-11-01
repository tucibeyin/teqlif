"""
LK admin operasyonları için multi-node aware utility'ler.

allocate_node  →  yeni kaynak yaratırken (load balance, tek node seçer)
lk_list_all_rooms  →  tüm node'lara list_rooms atar, union döner
lk_broadcast_delete  →  tüm node'lara delete_room atar, not_found sessiz

Bu tasarım 1 node, shared-Redis multi-node ve isolated multi-node
senaryolarının hepsinde doğru çalışır.

SRE-134: Sıralı for döngüsü → asyncio.gather paralel + 3.0s per-node timeout.
N=2 node'da max bekleme: 3.0s (eski: 2×4=8s sıralı).
"""

import asyncio
import logging
from typing import Optional

import aiohttp
from livekit.api import LiveKitAPI, DeleteRoomRequest
from livekit.api.room_service import RoomService, ListRoomsRequest

from app.config import settings
from app.services.edge_orchestrator import orchestrator

logger = logging.getLogger(__name__)

_PER_NODE_TIMEOUT = 3.0  # per-node HTTP/gRPC hard limit (saniye)
_GATHER_CEILING   = 5.0  # tüm gather için tavan (belt-and-suspenders)


# ---------------------------------------------------------------------------
# Per-node private helpers — raise on failure, caller handles via gather
# ---------------------------------------------------------------------------

async def _list_rooms_at(url: str) -> set[str]:
    async with aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=_PER_NODE_TIMEOUT)
    ) as session:
        svc = RoomService(session, url, settings.livekit_api_key, settings.livekit_api_secret)
        res = await svc.list_rooms(ListRoomsRequest())
        return {r.name for r in res.rooms}


async def _list_rooms_with_participants_at(url: str) -> dict[str, int]:
    async with aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=_PER_NODE_TIMEOUT)
    ) as session:
        svc = RoomService(session, url, settings.livekit_api_key, settings.livekit_api_secret)
        res = await svc.list_rooms(ListRoomsRequest())
        return {r.name: r.num_participants for r in res.rooms}


async def _delete_room_at(url: str, room_name: str) -> None:
    async with LiveKitAPI(
        url=url,
        api_key=settings.livekit_api_key,
        api_secret=settings.livekit_api_secret,
    ) as api:
        await asyncio.wait_for(
            api.room.delete_room(DeleteRoomRequest(room=room_name)),
            timeout=_PER_NODE_TIMEOUT,
        )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def lk_list_all_rooms() -> set[str]:
    """
    Tüm sağlıklı media node'larına ListRooms atar, oda isimlerinin union'ını döner.
    Paralel — N node'da toplam max bekleme _PER_NODE_TIMEOUT saniyedir.
    Hiçbir node'a erişilemediyse RuntimeError fırlatır.
    """
    nodes = await orchestrator.all_media_nodes()
    urls = [n.get("livekit_url", "") for n in nodes if n.get("livekit_url")]
    if not urls:
        return set()

    try:
        results = await asyncio.wait_for(
            asyncio.gather(*[_list_rooms_at(u) for u in urls], return_exceptions=True),
            timeout=_GATHER_CEILING,
        )
    except asyncio.TimeoutError:
        logger.error("[LK] lk_list_all_rooms: gather ceiling %ss aşıldı", _GATHER_CEILING)
        raise RuntimeError("[LK] LiveKit node gather timeout — aktif kayıtlara dokunulmayacak")

    all_rooms: set[str] = set()
    reachable = 0
    for url, r in zip(urls, results):
        if isinstance(r, Exception):
            logger.warning("[LK] lk_list_all_rooms: node=%s unreachable | %s", url, r)
        else:
            all_rooms.update(r)
            reachable += 1

    if urls and reachable == 0:
        raise RuntimeError("[LK] Hiçbir LiveKit node'una erişilemedi — aktif kayıtlara dokunulmayacak")

    logger.debug("[LK] lk_list_all_rooms: %d/%d node erişildi, %d room", reachable, len(urls), len(all_rooms))
    return all_rooms


async def lk_list_all_rooms_with_participants() -> dict[str, int]:
    """
    Tüm sağlıklı media node'larına ListRooms atar, {room_name: num_participants} döner.
    Paralel — aynı oda birden fazla node'da görünürse en yüksek participant sayısı kazanır.
    """
    nodes = await orchestrator.all_media_nodes()
    urls = [n.get("livekit_url", "") for n in nodes if n.get("livekit_url")]
    if not urls:
        return {}

    try:
        results = await asyncio.wait_for(
            asyncio.gather(*[_list_rooms_with_participants_at(u) for u in urls], return_exceptions=True),
            timeout=_GATHER_CEILING,
        )
    except asyncio.TimeoutError:
        logger.warning("[LK] lk_list_all_rooms_with_participants: gather ceiling %ss aşıldı", _GATHER_CEILING)
        return {}

    rooms: dict[str, int] = {}
    for url, r in zip(urls, results):
        if isinstance(r, Exception):
            logger.warning("[LK] lk_list_all_rooms_with_participants: node=%s unreachable | %s", url, r)
        else:
            for name, participants in r.items():
                rooms[name] = max(rooms.get(name, 0), participants)

    return rooms


async def lk_broadcast_delete(room_name: str, livekit_url: Optional[str] = None) -> None:
    """
    room_name'i tüm sağlıklı media node'larından siler.
    Paralel — livekit_url verilirse o URL listede önce yer alır.
    not_found / does_not_exist hataları sessiz yutulur (idempotent).
    """
    nodes = await orchestrator.all_media_nodes()

    urls: list[str] = []
    if livekit_url:
        urls.append(livekit_url)
    for node in nodes:
        url = node.get("livekit_url", "")
        if url and url not in urls:
            urls.append(url)

    if not urls:
        return

    async def _delete(url: str) -> None:
        try:
            await _delete_room_at(url, room_name)
            logger.debug("[LK] lk_broadcast_delete: deleted room=%s on %s", room_name, url)
        except asyncio.TimeoutError:
            logger.warning(
                "[LK] lk_broadcast_delete: timeout %ss | room=%s node=%s",
                _PER_NODE_TIMEOUT, room_name, url,
            )
        except Exception as exc:
            err = str(exc).lower()
            if "not_found" in err or "does not exist" in err:
                logger.debug("[LK] lk_broadcast_delete: room already gone | room=%s node=%s", room_name, url)
            else:
                logger.warning("[LK] lk_broadcast_delete: FAILED | room=%s node=%s | %s", room_name, url, exc)

    try:
        await asyncio.wait_for(
            asyncio.gather(*[_delete(u) for u in urls], return_exceptions=True),
            timeout=_GATHER_CEILING,
        )
    except asyncio.TimeoutError:
        logger.warning(
            "[LK] lk_broadcast_delete: gather ceiling %ss aşıldı | room=%s", _GATHER_CEILING, room_name
        )
