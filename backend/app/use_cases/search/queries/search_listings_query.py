import asyncio
from typing import Optional

from sqlalchemy import select, or_, func
from sqlalchemy import text as sa_text

from app.core.uow import AbstractUnitOfWork
from app.models.enums import ListingStatus
from app.models.listing import Listing
from app.models.user import User
from app.services.ml.ml_service import generate_embedding
from app.use_cases.search.queries.search_utils import (
    listing_dict,
    sanitize_ts_query,
    build_prefix_tsquery,
    raw_row_to_listing_dict,
)


class SearchListingsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, q: str, offset: int, current_user_id: Optional[int]) -> dict:
        q = q.strip()
        if not q:
            return {"listings": [], "search_type": "text"}

        words = q.split()

        # ── 1. Kısa (≤2 karakter) → ILIKE ─────────────────────────────────────
        if len(q) <= 2:
            return await self._ilike(q, offset)

        # ── 2. Uzun (≥3 kelime) → FAISS + pgvector semantic ──────────────────
        if len(words) >= 3:
            return await self._semantic(q, offset, current_user_id)

        # ── 3. Orta → Hybrid FTS + Semantic RRF ──────────────────────────────
        return await self._hybrid(q, offset, current_user_id)

    async def _ilike(self, q: str, offset: int) -> dict:
        term = f"%{q}%"
        stmt = (
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
        result = await self.uow.session.execute(stmt)
        return {"listings": [listing_dict(l, u) for l, u in result.all()], "search_type": "text"}

    async def _semantic(self, q: str, offset: int, current_user_id: Optional[int]) -> dict:
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

        from app.services.ml.faiss_service import faiss_search
        candidate_ids = await faiss_search(vector, k=80)

        if candidate_ids:
            id_list = ",".join(str(i) for i in candidate_ids)
            raw = sa_text(f"""
                SELECT
                    l.id, l.title, l.price, l.category, l.location,
                    l.image_url, l.image_urls, l.created_at,
                    u.id AS uid, u.username, u.full_name
                FROM listings l
                JOIN users u ON u.id = l.user_id
                WHERE l.id IN ({id_list})
                  AND l.status = 'active'
                  AND l.status != 'deleted'
                  AND l.embedding IS NOT NULL
                ORDER BY (
                    (1.0 - (l.embedding <=> CAST(:vec AS vector)))
                    {pref_clause}
                ) DESC
                LIMIT 12 OFFSET :offset
            """)
        else:
            params["threshold"] = 0.6
            raw = sa_text(f"""
                SELECT
                    l.id, l.title, l.price, l.category, l.location,
                    l.image_url, l.image_urls, l.created_at,
                    u.id AS uid, u.username, u.full_name
                FROM listings l
                JOIN users u ON u.id = l.user_id
                WHERE l.status = 'active'
                  AND l.status != 'deleted'
                  AND l.embedding IS NOT NULL
                  AND (l.embedding <=> CAST(:vec AS vector)) < :threshold
                ORDER BY (
                    (1.0 - (l.embedding <=> CAST(:vec AS vector)))
                    {pref_clause}
                ) DESC
                LIMIT 12 OFFSET :offset
            """)

        result = await self.uow.session.execute(raw, params)
        return {
            "listings": [raw_row_to_listing_dict(row) for row in result.fetchall()],
            "search_type": "semantic",
        }

    async def _hybrid(self, q: str, offset: int, current_user_id: Optional[int]) -> dict:
        ts_q = sanitize_ts_query(q)
        term = f"%{ts_q}%"
        prefix_q = build_prefix_tsquery(ts_q)
        if not prefix_q:
            return {"listings": [], "search_type": "text"}

        loop = asyncio.get_running_loop()
        embed_future = loop.run_in_executor(None, generate_embedding, ts_q)

        fts_params: dict = {"tsq_prefix": prefix_q, "term": term, "offset": offset}
        fts_pref_clause = ""
        if current_user_id:
            _pref = await self.uow.session.scalar(
                select(User.preference_embedding).where(User.id == current_user_id)
            )
            if _pref is not None:
                pref_str = "[" + ",".join(f"{x:.8f}" for x in _pref) + "]"
                fts_pref_clause = "+ (1.0 - (l.embedding <=> CAST(:fts_pref_vec AS vector))) * 0.15"
                fts_params["fts_pref_vec"] = pref_str

        faiss_ids: list[int] = []
        query_vec: list[float] = []
        try:
            query_vec = await embed_future
            from app.services.ml.faiss_service import faiss_search
            faiss_ids = await faiss_search(query_vec, k=40)
        except Exception:
            pass

        if faiss_ids:
            faiss_id_list = ",".join(str(i) for i in faiss_ids)
            fts_params["sem_vec"] = "[" + ",".join(f"{v:.8f}" for v in query_vec) + "]"
            rrf_raw = sa_text(f"""
                WITH fts_cte AS (
                    SELECT id, ROW_NUMBER() OVER (ORDER BY rank DESC) AS fts_rank
                    FROM (
                        SELECT l.id,
                               COALESCE(ts_rank(l.search_vector,
                                   to_tsquery('turkish', :tsq_prefix)), 0.0) AS rank
                        FROM listings l
                        WHERE l.status = 'active'
                          AND l.status != 'deleted'
                          AND (l.search_vector @@ to_tsquery('turkish', :tsq_prefix)
                               OR (l.search_vector IS NULL AND l.title ILIKE :term))
                        ORDER BY rank DESC
                        LIMIT 30
                    ) t
                ),
                sem_cte AS (
                    SELECT id, ROW_NUMBER() OVER (ORDER BY sim DESC) AS sem_rank
                    FROM (
                        SELECT l.id,
                               (1.0 - (l.embedding <=> CAST(:sem_vec AS vector))) AS sim
                        FROM listings l
                        WHERE l.id IN ({faiss_id_list})
                          AND l.status = 'active'
                          AND l.status != 'deleted'
                          AND l.embedding IS NOT NULL
                        ORDER BY sim DESC
                    ) t
                ),
                rrf_cte AS (
                    SELECT COALESCE(f.id, s.id) AS id,
                           COALESCE(1.0 / (60.0 + f.fts_rank), 0.0)
                           + COALESCE(1.0 / (60.0 + s.sem_rank), 0.0) AS rrf_score
                    FROM fts_cte f
                    FULL OUTER JOIN sem_cte s ON s.id = f.id
                )
                SELECT
                    l.id, l.title, l.price, l.category, l.location,
                    l.image_url, l.image_urls, l.created_at,
                    u.id AS uid, u.username, u.full_name
                FROM rrf_cte r
                JOIN listings l ON l.id = r.id
                JOIN users u ON u.id = l.user_id
                ORDER BY (r.rrf_score {fts_pref_clause}) DESC
                LIMIT 12 OFFSET :offset
            """)
            result = await self.uow.session.execute(rrf_raw, fts_params)
        else:
            fts_raw = sa_text(f"""
                SELECT
                    l.id, l.title, l.price, l.category, l.location,
                    l.image_url, l.image_urls, l.created_at,
                    u.id AS uid, u.username, u.full_name
                FROM listings l
                JOIN users u ON u.id = l.user_id
                WHERE l.status = 'active'
                  AND l.status != 'deleted'
                  AND (
                      l.search_vector @@ to_tsquery('turkish', :tsq_prefix)
                      OR (l.search_vector IS NULL AND l.title ILIKE :term)
                  )
                ORDER BY (
                    COALESCE(ts_rank(l.search_vector,
                        to_tsquery('turkish', :tsq_prefix)), 0.0) * 0.85
                    {fts_pref_clause}
                ) DESC
                LIMIT 12 OFFSET :offset
            """)
            result = await self.uow.session.execute(fts_raw, fts_params)

        rows = result.fetchall()
        return {
            "listings": [raw_row_to_listing_dict(row) for row in rows],
            "search_type": "text",
        }
