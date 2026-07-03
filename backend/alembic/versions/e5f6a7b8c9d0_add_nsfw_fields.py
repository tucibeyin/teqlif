"""add nsfw_score and nsfw_checked_at to listings

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-07-04 06:05:00.000000

"""
from alembic import op

revision = 'e5f6a7b8c9d0'
down_revision = 'd4e5f6a7b8c9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS nsfw_score FLOAT")
    op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS nsfw_checked_at TIMESTAMP WITH TIME ZONE")


def downgrade() -> None:
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS nsfw_checked_at")
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS nsfw_score")
