from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.models.enums import ListingStatus
from app.database import get_db
from app.models.report import Report
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import NotFoundException, ForbiddenException

router = APIRouter(prefix="/api/reports", tags=["reports"])


class ReportCreateSchema(BaseModel):
    listing_id: int
    reason: str = Field(min_length=3, max_length=1000)


@router.post("")
async def report_listing(
    payload: ReportCreateSchema,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    listing = await db.scalar(
        select(Listing).where(
            Listing.id == payload.listing_id,
            Listing.status == ListingStatus.ACTIVE,
        )
    )
    if not listing:
        raise NotFoundException(code="LISTING_NOT_FOUND")
    if listing.user_id == current_user.id:
        raise ForbiddenException(code="SELF_REPORT_FORBIDDEN")

    stmt = (
        pg_insert(Report)
        .values(
            listing_id=payload.listing_id,
            reporter_id=current_user.id,
            reason=payload.reason,
        )
        .on_conflict_do_nothing(
            index_elements=["reporter_id", "listing_id"],
        )
    )
    await db.execute(stmt)
    await db.commit()
    return {"ok": True}
