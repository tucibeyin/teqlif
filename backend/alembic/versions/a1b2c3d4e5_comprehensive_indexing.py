"""Comprehensive indexing for Feed, Search and Analytics

Revision ID: a1b2c3d4e5
Revises: optim_ai_price
Create Date: 2026-07-06 13:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5'
down_revision: Union[str, None] = 'd185a1186754'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. pg_trgm eklentisi
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")
    
    # 2. Feed İndeksleri (Kompozit)
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_feed_organic ON listings (category, is_active, is_deleted, created_at DESC);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_feed_recent ON listings (is_active, is_deleted, created_at DESC);")
    
    # 3. Trigram İndeksleri (Arama)
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_title_trgm ON listings USING gin (title gin_trgm_ops);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_desc_trgm ON listings USING gin (description gin_trgm_ops);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_username_trgm ON users USING gin (username gin_trgm_ops);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_fullname_trgm ON users USING gin (full_name gin_trgm_ops);")
    
    # 4. Analytics İndeksleri (Zaman Serisi)
    op.execute("CREATE INDEX IF NOT EXISTS ix_live_streams_started_at ON live_streams (started_at);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_auctions_ended_at ON auctions (ended_at);")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_auctions_ended_at;")
    op.execute("DROP INDEX IF EXISTS ix_live_streams_started_at;")
    
    op.execute("DROP INDEX IF EXISTS ix_users_fullname_trgm;")
    op.execute("DROP INDEX IF EXISTS ix_users_username_trgm;")
    op.execute("DROP INDEX IF EXISTS ix_listings_desc_trgm;")
    op.execute("DROP INDEX IF EXISTS ix_listings_title_trgm;")
    
    op.execute("DROP INDEX IF EXISTS ix_listings_feed_recent;")
    op.execute("DROP INDEX IF EXISTS ix_listings_feed_organic;")
