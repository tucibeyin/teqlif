import asyncio
import json
import logging
from typing import Callable, Awaitable, Any, Dict
from fastapi import WebSocket, WebSocketDisconnect
from dataclasses import dataclass
from app.core.event_bus import event_bus
from app.core.events import DomainEvent

logger = logging.getLogger(__name__)

@dataclass
class ClientDisconnectedEvent(DomainEvent):
    """Bir WebSocket istemcisi bağlantıyı kestiğinde yayınlanır."""
    user_id: int
    topic: str = None
    reason: str = None

class WsGateway:
    """
    WebSocket yaşam döngüsünü ve bağlantı kopmalarını (RuntimeError) yönetir.
    Router katmanından while True döngüsünü soyutlar.
    """
    
    @staticmethod
    async def run_message_loop(
        websocket: WebSocket,
        user_id: int,
        topic: str,
        on_message: Callable[[Dict[str, Any]], Awaitable[None]],
        timeout_secs: float = 40.0,
    ):
        """
        Gelen WebSocket mesajlarını dinler ve on_message callback'ine yönlendirir.
        Kopma durumlarında (Timeout, Disconnect, RuntimeError) döngüyü sessizce
        kırar ve EventBus üzerinden ClientDisconnectedEvent fırlatır.
        """
        try:
            while True:
                try:
                    text = await asyncio.wait_for(
                        websocket.receive_text(), 
                        timeout=timeout_secs
                    )
                except asyncio.TimeoutError:
                    logger.warning("[WsGateway] Ping timeout | user_id=%s topic=%s", user_id, topic)
                    break
                except WebSocketDisconnect:
                    break
                except RuntimeError as exc:
                    # Starlette socket kapanmalarında sessizce döngüyü kırar
                    if "not connected" in str(exc).lower() or "close message" in str(exc).lower():
                        break
                    raise
                    
                if not text or text.strip() == "ping":
                    continue
                    
                try:
                    payload = json.loads(text)
                    await on_message(payload)
                except Exception as e:
                    logger.warning("[WsGateway] Mesaj işleme hatası | user=%s topic=%s : %s", user_id, topic, e)
        finally:
            event_bus.publish(ClientDisconnectedEvent(user_id=user_id, topic=topic, reason="disconnected"))

ws_gateway = WsGateway()
