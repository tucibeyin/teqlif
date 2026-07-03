"""add image_phash to listings

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-07-04 06:00:00.000000

"""
from alembic import op

revision = 'd4e5f6a7b8c9'
down_revision = 'c3d4e5f6a7b8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS image_phash VARCHAR(16)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_image_phash ON listings (image_phash)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_image_phash")
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS image_phash")
