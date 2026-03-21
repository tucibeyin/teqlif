"""add image_urls is_deleted listing_id thumbnail_url

Revision ID: 3a55d47f47f1
Revises: c1e3a52f8b19
Create Date: 2026-03-17

"""
from alembic import op


revision = '3a55d47f47f1'
down_revision = 'c1e3a52f8b19'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS image_urls TEXT")
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE")
    op.execute("ALTER TABLE auctions ADD COLUMN IF NOT EXISTS listing_id INTEGER REFERENCES listings(id)")
    op.execute("ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS thumbnail_url VARCHAR(500)")


def downgrade() -> None:
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS thumbnail_url")
    op.execute("ALTER TABLE auctions DROP COLUMN IF EXISTS listing_id")
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS is_deleted")
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS image_urls")
