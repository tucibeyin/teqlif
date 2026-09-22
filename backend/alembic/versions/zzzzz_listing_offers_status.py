"""feat: listing_offers — status + updated_at kolonu (TASK-yeni-A)

Revision ID: zzzzz_listing_offers_status
Revises: zzzzy_composite_indexes
Create Date: 2026-09-22 14:00:00.000000
"""
from alembic import op

revision = "zzzzz_listing_offers_status"
down_revision = "zzzzy_composite_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE listing_offers ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'")
    op.execute("ALTER TABLE listing_offers ADD COLUMN updated_at TIMESTAMPTZ")


def downgrade() -> None:
    op.execute("ALTER TABLE listing_offers DROP COLUMN IF EXISTS updated_at")
    op.execute("ALTER TABLE listing_offers DROP COLUMN IF EXISTS status")
