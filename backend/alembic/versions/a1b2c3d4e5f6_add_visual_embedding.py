"""add visual_embedding to listings

Revision ID: a1b2c3d4e5f6
Revises: z2a3b4c5d6e7
Create Date: 2026-07-04 04:30:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'a1b2c3d4e5f6'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # CLIP ViT-B/32 → 512 boyutlu görsel embedding
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS visual_embedding vector(512)")
    op.execute(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_listings_visual_embedding "
        "ON listings USING ivfflat (visual_embedding vector_cosine_ops) WITH (lists = 50)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_visual_embedding")
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS visual_embedding")
