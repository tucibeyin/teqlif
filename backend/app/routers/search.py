from typing import Optional

from fastapi import APIRouter, Depends, Request

from app.core.rate_limit import limiter
from app.core.uow import SqlAlchemyUnitOfWork
from app.database import get_uow
from app.utils.auth import bearer_scheme, decode_token
from app.use_cases.search.queries.search_users_query import SearchUsersQuery
from app.use_cases.search.queries.explore_query import ExploreQuery
from app.use_cases.search.queries.search_all_query import SearchAllQuery
from app.use_cases.search.queries.search_listings_query import SearchListingsQuery

router = APIRouter(prefix="/api/search", tags=["search"])


async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("/users")
@limiter.limit("30/minute")
async def search_users(
    request: Request,
    q: str = "",
    offset: int = 0,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await SearchUsersQuery(uow).execute(q, offset, current_user_id)


@router.get("/explore")
async def explore(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await ExploreQuery(uow).execute(current_user_id)


@router.get("/all")
@limiter.limit("30/minute")
async def search_all(
    request: Request,
    q: str = "",
    offset: int = 0,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await SearchAllQuery(uow).execute(q, offset, current_user_id)


@router.get("/listings")
@limiter.limit("30/minute")
async def search_listings(
    request: Request,
    q: str = "",
    offset: int = 0,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await SearchListingsQuery(uow).execute(q, offset, current_user_id)
