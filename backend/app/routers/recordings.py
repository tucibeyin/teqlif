from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user
from app.use_cases.streams.queries.get_my_recordings import GetMyRecordingsQuery

router = APIRouter(prefix="/api/recordings", tags=["recordings"])


@router.get("/my")
async def get_my_recordings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Host'un son 30 günlük kayıtlarını döner. PRO kontrolü zorunlu değil —
    kayıtlar herkese ait; sadece presigned URL için PRO gerekir."""
    return await GetMyRecordingsQuery(db).execute(host_id=current_user.id)
