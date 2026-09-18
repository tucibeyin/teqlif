"""remove visual_embedding from listings

Revision ID: zzzzt_remove_visual_emb
Revises: zzzzs_perf_indexes
Create Date: 2026-09-18 14:06:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzt_remove_visual_emb'
down_revision = 'zzzzs_perf_indexes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Drop index first
    op.execute("DROP INDEX IF EXISTS ix_listings_visual_embedding")
    # Drop column
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS visual_embedding")


def downgrade() -> None:
    # Add column back
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS visual_embedding vector(512)")
    # Add index back
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listings_visual_embedding "
        "ON listings USING ivfflat (visual_embedding vector_cosine_ops) WITH (lists = 50)"
    )
