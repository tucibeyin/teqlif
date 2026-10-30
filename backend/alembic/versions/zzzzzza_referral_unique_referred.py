"""referrals.referred_id UNIQUE kısıtı (SRE-20 — çift harcama race condition)

Revision ID: zzzzzza_referral_unique
Revises: zzzzzz_stream_total_likes
Create Date: 2026-10-30
"""
from alembic import op

revision = "zzzzzza_referral_unique"
down_revision = "zzzzz0_searchalert_enum_fix"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE referrals
            ADD CONSTRAINT uq_referrals_referred_id UNIQUE (referred_id)
    """)


def downgrade() -> None:
    op.execute("""
        ALTER TABLE referrals
            DROP CONSTRAINT IF EXISTS uq_referrals_referred_id
    """)
