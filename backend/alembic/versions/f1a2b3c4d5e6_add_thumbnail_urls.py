"""add profile_image_thumb_url to users and thumbnail_url to listings

Revision ID: f1a2b3c4d5e6
Revises: e4f5a6b7c8d9
Create Date: 2026-03-23

"""
from alembic import op


revision = 'f1a2b3c4d5e6'
down_revision = 'e4f5a6b7c8d9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_image_thumb_url VARCHAR(500)"
    )
    op.execute(
        "ALTER TABLE listings ADD COLUMN IF NOT EXISTS thumbnail_url VARCHAR(500)"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS thumbnail_url")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS profile_image_thumb_url")
