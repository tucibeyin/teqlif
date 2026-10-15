"""
LK admin operasyonları için multi-node aware utility'ler.

allocate_node  →  yeni kaynak yaratırken (load balance, tek node seçer)
lk_list_all_rooms  →  tüm node'lara list_rooms atar, union döner
lk_broadcast_delete  →  tüm node'lara delete_room atar, not_found sessiz

Bu tasarım 1 node, shared-Redis multi-node ve isolated multi-node
senaryolarının hepsinde doğru çalışır.
"""

import logging
from typing import Optional

import aiohttp
from livekit.api import LiveKitAPI, DeleteRoomRequest
from livekit.api.room_service import RoomService, ListRoomsRequest

from app.config import settings
from app.services.edge_orchestrator import orchestrator

logger = logging.getLogger(__name__)


async def lk_list_all_rooms() -> set[str]:
    """
    Tüm sağlıklı media node'larına ListRooms atar, oda isimlerinin union'ını döner.
    Bir node'a erişilemezse loglanır ama diğerleri sorgulanmaya devam eder.
    Hiçbir node'a erişilemediyse RuntimeError fırlatır — çağıran yer boş kümeyi
    "aktif oda yok" olarak yorumlayıp aktif kayıtları silmesin.
    """
    nodes = await orchestrator.all_media_nodes()
    all_rooms: set[str] = set()
    reachable = 0
    _timeout = aiohttp.ClientTimeout(total=4.0)
    for node in nodes:
        url = node.get("livekit_url", "")
        if not url:
            continue
        try:
            async with aiohttp.ClientSession(timeout=_timeout) as session:
                svc = RoomService(session, url, settings.livekit_api_key, settings.livekit_api_secret)
                res = await svc.list_rooms(ListRoomsRequest())
                all_rooms.update(r.name for r in res.rooms)
                reachable += 1
        except Exception as exc:
            logger.warning("[LK] lk_list_all_rooms: node=%s unreachable | %s", url, exc)

    if nodes and reachable == 0:
        raise RuntimeError("[LK] Hiçbir LiveKit node'una erişilemedi — aktif kayıtlara dokunulmayacak")

    logger.debug("[LK] lk_list_all_rooms: %d/%d node erişildi, %d room", reachable, len(nodes), len(all_rooms))
    return all_rooms


async def lk_list_all_rooms_with_participants() -> dict[str, int]:
    """
    Tüm sağlıklı media node'larına ListRooms atar, {room_name: num_participants} döner.
    Aynı oda birden fazla node'da görünürse en yüksek participant sayısı kazanır.
    """
    nodes = await orchestrator.all_media_nodes()
    rooms: dict[str, int] = {}
    _timeout = aiohttp.ClientTimeout(total=4.0)
    for node in nodes:
        url = node.get("livekit_url", "")
        if not url:
            continue
        try:
            async with aiohttp.ClientSession(timeout=_timeout) as session:
                svc = RoomService(session, url, settings.livekit_api_key, settings.livekit_api_secret)
                res = await svc.list_rooms(ListRoomsRequest())
                for r in res.rooms:
                    rooms[r.name] = max(rooms.get(r.name, 0), r.num_participants)
        except Exception as exc:
            logger.warning("[LK] lk_list_all_rooms_with_participants: node=%s unreachable | %s", url, exc)
    return rooms


async def lk_broadcast_delete(room_name: str, livekit_url: Optional[str] = None) -> None:
    """
    room_name'i tüm sağlıklı media node'larından siler.
    livekit_url verilirse önce o URL'e istek atılır; sonra diğer node'lara da broadcast yapılır.
    not_found / does_not_exist hataları sessiz yutulur (idempotent).
    """
    nodes = await orchestrator.all_media_nodes()

    # Bilinen URL en başa al — hem tutarlılık hem öncelik sırası için
    urls: list[str] = []
    if livekit_url:
        urls.append(livekit_url)
    for node in nodes:
        url = node.get("livekit_url", "")
        if url and url not in urls:
            urls.append(url)

    for url in urls:
        try:
            async with LiveKitAPI(
                url=url,
                api_key=settings.livekit_api_key,
                api_secret=settings.livekit_api_secret,
            ) as api:
                await api.room.delete_room(DeleteRoomRequest(room=room_name))
            logger.debug("[LK] lk_broadcast_delete: deleted room=%s on %s", room_name, url)
        except Exception as exc:
            err = str(exc).lower()
            if "not_found" in err or "does not exist" in err:
                logger.debug("[LK] lk_broadcast_delete: room already gone | room=%s node=%s", room_name, url)
            else:
                logger.warning("[LK] lk_broadcast_delete: FAILED | room=%s node=%s | %s", room_name, url, exc)
