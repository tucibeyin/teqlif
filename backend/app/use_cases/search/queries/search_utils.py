import json
from typing import Optional

from sqlalchemy import select

from app.models.block import UserBlock
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.user import User


def sanitize_ts_query(q: str) -> str:
    return " ".join(q.split())


def build_prefix_tsquery(q: str) -> str:
    from app.services.ml.turkish_nlp import build_stemmed_tsquery
    return build_stemmed_tsquery(q)


def block_filters(query, model_id_col, current_user_id: int):
    """Bilateral block filtresi — sadece user araması için kullanılır."""
    blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    blocking_me = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    return query.where(
        model_id_col.not_in(blocked_by_me),
        model_id_col.not_in(blocking_me),
    )


def listing_dict(l: Listing, u: User) -> dict:
    return {
        "id": l.id,
        "title": l.title,
        "price": l.price,
        "category": l.category,
        "location": l.location,
        "image_url": l.image_url,
        "image_urls": json.loads(l.image_urls) if l.image_urls else [],
        "created_at": l.created_at.isoformat() if l.created_at else None,
        "user": {"id": u.id, "username": u.username, "full_name": u.full_name},
    }


def stream_dict(s: LiveStream) -> dict:
    return {
        "id": s.id,
        "room_name": s.room_name,
        "title": s.title,
        "category": s.category,
        "thumbnail_url": s.thumbnail_url,
        "started_at": s.started_at.isoformat() if s.started_at else None,
        "host": {
            "id": s.host.id,
            "username": s.host.username,
            "full_name": s.host.full_name,
        },
    }


def raw_row_to_listing_dict(row) -> dict:
    return {
        "id": row[0],
        "title": row[1],
        "price": row[2],
        "category": row[3],
        "location": row[4],
        "image_url": row[5],
        "image_urls": json.loads(row[6]) if row[6] else [],
        "created_at": row[7].isoformat() if row[7] else None,
        "user": {"id": row[8], "username": row[9], "full_name": row[10]},
    }
