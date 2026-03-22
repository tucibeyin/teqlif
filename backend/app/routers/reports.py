from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.report import Report
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import NotFoundException, BadRequestException, ConflictException

router = APIRouter(prefix="/api/reports", tags=["reports"])


@router.post("")
async def report_listing(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    listing_id = payload.get("listing_id")
    reason = (payload.get("reason") or "").strip()
    if not listing_id or not reason:
        raise BadRequestException("listing_id ve reason zorunludur")

    listing = await db.scalar(select(Listing).where(Listing.id == listing_id, Listing.is_active.is_(True)))
    if not listing:
        raise NotFoundException("İlan bulunamadı")
    if listing.user_id == current_user.id:
        raise BadRequestException("Kendi ilanınızı şikayet edemezsiniz")

    # Aynı kullanıcı aynı ilanı tekrar şikayet edemez
    existing = await db.scalar(
        select(Report).where(Report.listing_id == listing_id, Report.reporter_id == current_user.id)
    )
    if existing:
        raise ConflictException("Bu ilanı zaten şikayet ettiniz")

    db.add(Report(listing_id=listing_id, reporter_id=current_user.id, reason=reason))
    await db.commit()
    return {"ok": True}
