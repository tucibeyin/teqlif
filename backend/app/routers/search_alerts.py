"""
Arama Alarmları — kullanıcı belirli kategori + fiyat filtresiyle alarm oluşturur,
eşleşen ilan eklendiğinde push bildirimi alır.

Limit: kullanıcı başına en fazla 5 aktif alarm.
"""
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.models.enums import SearchAlertStatus
from app.database import get_db
from app.models.search_alert import SearchAlert
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException, ForbiddenException, NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/search-alerts", tags=["search-alerts"])

_MAX_ALERTS_PER_USER = 5


class SearchAlertCreate(BaseModel):
    category: Optional[str] = Field(None, max_length=50)
    query: Optional[str] = Field(None, max_length=200)
    max_price: Optional[float] = Field(None, gt=0)


@router.get("")
async def list_alerts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(SearchAlert)
        .where(SearchAlert.user_id == current_user.id, SearchAlert.status == SearchAlertStatus.ACTIVE)  # noqa: E712
        .order_by(SearchAlert.created_at.desc())
    )
    alerts = result.scalars().all()
    return [
        {
            "id": a.id,
            "category": a.category,
            "query": a.query,
            "max_price": a.max_price,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        }
        for a in alerts
    ]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_alert(
    payload: SearchAlertCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not payload.category and not payload.query:
        raise BadRequestException("Kategori veya arama kelimesi zorunludur")

    count_result = await db.execute(
        select(func.count()).where(
            SearchAlert.user_id == current_user.id,
            SearchAlert.status == SearchAlertStatus.ACTIVE,  # noqa: E712
        )
    )
    active_count = count_result.scalar_one()
    if active_count >= _MAX_ALERTS_PER_USER:
        raise BadRequestException(f"En fazla {_MAX_ALERTS_PER_USER} aktif alarm oluşturabilirsiniz")

    alert = SearchAlert(
        user_id=current_user.id,
        category=payload.category,
        query=payload.query,
        max_price=payload.max_price,
    )
    db.add(alert)
    await db.commit()
    await db.refresh(alert)
    logger.info("[SearchAlert] Oluşturuldu | user_id=%s id=%s", current_user.id, alert.id)
    return {"id": alert.id, "message": "Alarm oluşturuldu"}


@router.delete("/{alert_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_alert(
    alert_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(SearchAlert).where(SearchAlert.id == alert_id)
    )
    alert = result.scalar_one_or_none()
    if not alert:
        raise NotFoundException("Alarm bulunamadı")
    if alert.user_id != current_user.id:
        raise ForbiddenException("Bu alarma erişim yetkiniz yok")

    alert.status = 'passive'
    await db.commit()
