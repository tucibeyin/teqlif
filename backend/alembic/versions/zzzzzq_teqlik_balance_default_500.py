"""teqlik_balance_default_500: kayıt bonusunu 100'den 500'e yükselt

Revision ID: zzzzzq_teqlik_balance_default_500
Revises: zzzzzp_calls_livekit_url
Create Date: 2026-10-17
"""
from alembic import op

revision = "zzzzzq_teqlik_balance_default_500"
down_revision = "zzzzzp_calls_livekit_url"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE users ALTER COLUMN teqlik_balance SET DEFAULT 500"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE users ALTER COLUMN teqlik_balance SET DEFAULT 100"
    )
