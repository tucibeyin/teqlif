"""
Direkt Satış router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, uow, rate-limit) alır
  2. Command fonksiyonunu çağırır ve sonucu döner

İş mantığı tamamen use_cases/direct_sales/commands/direct_sale_commands.py içindedir.
"""
from fastapi import APIRouter, Depends, Request

from app.database import get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.user import User
from app.schemas.direct_sale import (
    DirectSaleStartIn, DirectSaleCancelIn,
    DirectSaleStateOut,
)
from app.utils.auth import get_current_user
from app.core.rate_limit import limiter, get_user_id_or_ip
from app.use_cases.direct_sales.commands import direct_sale_commands as cmd

router = APIRouter(prefix="/api/direct-sales", tags=["direct-sales"])


# ── GET ───────────────────────────────────────────────────────────────────────

@router.get("/{stream_id}/state", response_model=DirectSaleStateOut)
async def get_sale_state(stream_id: int):
    """Redis-only okuma — herkes erişebilir, auth gerekmez."""
    return await cmd.get_sale_state(stream_id)


# ── Host komutları ────────────────────────────────────────────────────────────

@router.post("/{stream_id}/start")
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def start_sale(
    request: Request,
    stream_id: int,
    data: DirectSaleStartIn,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await cmd.start_sale(stream_id, data, current_user, uow)


@router.post("/{sale_id}/pause")
async def pause_sale(
    sale_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    await cmd.pause_sale(sale_id, current_user, uow)
    return {"success": True}


@router.post("/{sale_id}/resume")
async def resume_sale(
    sale_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    await cmd.resume_sale(sale_id, current_user, uow)
    return {"success": True}


@router.post("/{sale_id}/end")
async def end_sale(
    sale_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    await cmd.end_sale(sale_id, current_user, uow)
    return {"success": True}


@router.post("/{sale_id}/cancel")
async def cancel_sale(
    sale_id: int,
    data: DirectSaleCancelIn,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    await cmd.cancel_sale(sale_id, data, current_user, uow)
    return {"success": True}
