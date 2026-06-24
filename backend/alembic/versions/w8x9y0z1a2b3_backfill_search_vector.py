"""backfill search_vector for existing listings

Revision ID: w8x9y0z1a2b3
Revises: v7w8x9y0z1a2
Create Date: 2026-06-24 00:00:00.000000
"""
from alembic import op

revision = "w8x9y0z1a2b3"
down_revision = "v7w8x9y0z1a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        UPDATE listings
        SET search_vector = to_tsvector(
            'turkish',
            coalesce(title, '') || ' ' || coalesce(description, '')
        )
        WHERE search_vector IS NULL
          AND is_deleted = FALSE
    """)


def downgrade() -> None:
    pass
