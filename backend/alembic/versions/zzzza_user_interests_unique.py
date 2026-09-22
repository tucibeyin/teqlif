"""perf: user_interests UNIQUE constraint — subcategory dahil NULLS NOT DISTINCT (TASK-yeni-B)

Revision ID: zzzza_user_interests_unique
Revises: zzzzz_listing_offers_status
Create Date: 2026-09-22 14:30:00.000000
"""
from alembic import op

revision = "zzzza_user_interests_unique"
down_revision = "zzzzz_listing_offers_status"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE user_interests DROP CONSTRAINT IF EXISTS uq_user_interest")
    op.execute("""
        ALTER TABLE user_interests
        ADD CONSTRAINT uq_user_interest
        UNIQUE NULLS NOT DISTINCT (user_id, category, subcategory)
    """)


def downgrade() -> None:
    op.execute("ALTER TABLE user_interests DROP CONSTRAINT IF EXISTS uq_user_interest")
    op.execute(
        "ALTER TABLE user_interests ADD CONSTRAINT uq_user_interest UNIQUE (user_id, category)"
    )
