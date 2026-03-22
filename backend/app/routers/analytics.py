import logging
from fastapi import APIRouter, Depends, Request, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.analytics import AnalyticsEvent
from app.schemas.analytics import AnalyticsEventCreate
from app.utils.auth import decode_token

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/analytics", tags=["analytics"])

async def _save_event_async(data: AnalyticsEventCreate, user_id: int | None, ip_address: str | None, db: AsyncSession):
    try:
        event = AnalyticsEvent(
            session_id=data.session_id,
            user_id=user_id,
            event_type=data.event_type,
            url=data.url,
            device_type=data.device_type,
            os=data.os,
            browser=data.browser,
            ip_address=ip_address,
            event_metadata=data.event_metadata,
        )
        db.add(event)
        await db.commit()
    except Exception as exc:
        logger.error("[ANALYTICS] Error saving event: %s", exc)

@router.post("/track", status_code=202)
async def track_event(
    data: AnalyticsEventCreate,
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
):
    """
    Receives tracking events from web or mobile clients.
    Uses BackgroundTasks for latency-free responses.
    """
    # Try to extract user_id if token is present in Authorization header
    user_id = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
        try:
            user_id = decode_token(token)
        except Exception:
            pass

    # Extract IP address safely
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        ip_address = forwarded.split(",")[0].strip()
    else:
        ip_address = request.client.host if request.client else None

    # Save to database asynchronously in the background
    background_tasks.add_task(_save_event_async, data, user_id, ip_address, db)

    return {"status": "queued"}
