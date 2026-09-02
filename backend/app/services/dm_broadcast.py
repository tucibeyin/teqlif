from app.core.ws_manager import ws_manager

DM_CHANNEL = "dm_broadcast"


async def broadcast_dm(user_id: int, payload: dict) -> None:
    await ws_manager.publish(DM_CHANNEL, f"dm:{user_id}", payload)
