import asyncio
import json
from typing import Optional

from sqlalchemy import select, or_, func
from sqlalchemy import text as sa_text

from app.core.uow import AbstractUnitOfWork
from app.models.enums import ListingStatus, UserStatus
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.user import User
from app.services.ml.ml_service import generate_embedding
from app.use_cases.search.queries.search_utils import (
    block_filters,
    listing_dict,
    stream_dict,
    sanitize_ts_query,
    build_prefix_tsquery,
    raw_row_to_listing_dict,
)


class SearchAllQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, q: str, offset: int, current_user_id: Optional[int]) -> dict:
        q = q.strip()
        if not q:
            return {"users": [], "listings": [], "streams": [], "search_type": "text"}

        term = f"%{q}%"
        words = q.split()

        # ── Kullanıcılar (block filter KORU) ──────────────────────────────────
        user_q = (
            select(User)
            .where(
                User.status == UserStatus.ACTIVE,
                or_(User.username.ilike(term), User.full_name.ilike(term)),
            )
            .offset(offset)
            .limit(10)
        )
        if current_user_id:
            user_q = block_filters(user_q, User.id, current_user_id)
        users_result = await self.uow.session.execute(user_q)
        users = [
            {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            }
            for u in users_result.scalars().all()
        ]

        # ── Canlı yayınlar (block filter KALDIR — pasif izleme serbest) ───────
        stream_q = (
            select(LiveStream)
            .where(
                LiveStream.is_live == True,  # noqa: E712
                LiveStream.title.ilike(term),
            )
            .order_by(LiveStream.started_at.desc())
            .limit(6)
        )
        streams_result = await self.uow.session.execute(stream_q)
        streams = [stream_dict(s) for s in streams_result.scalars().all()]

        # ── İlanlar (block filter KALDIR — ilanlar herkese açık) ─────────────
        search_type = "text"
        listings: list[dict] = []

        if len(q) <= 2:
            listing_q = (
                select(Listing, User)
                .join(User, User.id == Listing.user_id)
                .where(
                    Listing.status == ListingStatus.ACTIVE,
                    Listing.status != ListingStatus.DELETED,
                    or_(Listing.title.ilike(term), Listing.description.ilike(term)),
                )
                .order_by(func.coalesce(Listing.reactivated_at, Listing.created_at).desc())
                .offset(offset)
                .limit(12)
            )
            result = await self.uow.session.execute(listing_q)
            listings = [listing_dict(l, u) for l, u in result.all()]

        elif len(words) >= 3:
            search_type = "semantic"
            loop = asyncio.get_running_loop()
            vector: list[float] = await loop.run_in_executor(None, generate_embedding, q)
            vec_str = "[" + ",".join(f"{v:.8f}" for v in vector) + "]"

            params: dict = {"vec": vec_str, "offset": offset}

            pref_clause = ""
            if current_user_id:
                _pref = await self.uow.session.scalar(
                    select(User.preference_embedding).where(User.id == current_user_id)
                )
                if _pref is not None:
                    pref_str = "[" + ",".join(f"{x:.8f}" for x in _pref) + "]"
                    pref_clause = "+ (1.0 - (l.embedding <=> CAST(:pref_vec AS vector))) * 0.15"
                    params["pref_vec"] = pref_str

            from app.services.ml.faiss_service import faiss_search as _faiss_search
            faiss_ids = await _faiss_search(vector, k=80)
            if faiss_ids:
                id_list = ",".join(str(i) for i in faiss_ids)
                where_clause = f"l.id IN ({id_list}) AND l.embedding IS NOT NULL"
            else:
                where_clause = "l.embedding IS NOT NULL AND (l.embedding <=> CAST(:vec AS vector)) < 0.6"

            raw = sa_text(f"""
                SELECT
                    l.id, l.title, l.price, l.category, l.location,
                    l.image_url, l.image_urls, l.created_at,
                    u.id AS uid, u.username, u.full_name
                FROM listings l
                JOIN users u ON u.id = l.user_id
                WHERE {where_clause}
                  AND l.status = 'active'
                  AND l.status != 'deleted'
                ORDER BY (
                    (1.0 - (l.embedding <=> CAST(:vec AS vector)))
                    {pref_clause}
                ) DESC
                LIMIT 12 OFFSET :offset
            """)
            result = await self.uow.session.execute(raw, params)
            listings = [raw_row_to_listing_dict(row) for row in result.fetchall()]

        else:
            ts_q = sanitize_ts_query(q)
            term_fts = f"%{ts_q}%"
            prefix_q = build_prefix_tsquery(ts_q)

            all_params: dict = {"tsq_prefix": prefix_q, "term": term_fts, "offset": offset}
            pref_expr = "0.0"
            if prefix_q and current_user_id:
                _pref = await self.uow.session.scalar(
                    select(User.preference_embedding).where(User.id == current_user_id)
                )
                if _pref is not None:
                    all_params["all_pref_vec"] = "[" + ",".join(f"{x:.8f}" for x in _pref) + "]"
                    pref_expr = "COALESCE((1.0 - (l.embedding <=> CAST(:all_pref_vec AS vector))) * 0.15, 0.0)"

            if prefix_q:
                all_raw = sa_text(f"""
                    SELECT
                        l.id, l.title, l.price, l.category, l.location,
                        l.image_url, l.image_urls, l.created_at,
                        u.id AS uid, u.username, u.full_name
                    FROM listings l
                    JOIN users u ON u.id = l.user_id
                    WHERE l.status = 'active'
                      AND l.status != 'deleted'
                      AND (l.search_vector @@ to_tsquery('turkish', :tsq_prefix)
                           OR (l.search_vector IS NULL AND l.title ILIKE :term))
                    ORDER BY (
                        COALESCE(ts_rank(l.search_vector,
                            to_tsquery('turkish', :tsq_prefix)), 0.0) * 0.85
                        + {pref_expr}
                    ) DESC
                    LIMIT 12 OFFSET :offset
                """)
                result = await self.uow.session.execute(all_raw, all_params)
                listings = [raw_row_to_listing_dict(row) for row in result.fetchall()]

        # ── ClickHouse: Kategori talep trendi (yalnızca ilk sayfa) ───────────
        if offset == 0 and listings:
            from collections import Counter
            from app.database_clickhouse import buffer_search_event
            cat_counts = Counter(l["category"] for l in listings if l.get("category"))
            if cat_counts:
                top_cat, _ = cat_counts.most_common(1)[0]
                asyncio.ensure_future(buffer_search_event(
                    user_id=current_user_id,
                    query=q,
                    category=top_cat,
                    result_count=len(listings),
                ))

        return {
            "users": users,
            "listings": listings,
            "streams": streams,
            "search_type": search_type,
        }
