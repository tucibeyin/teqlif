"""subscription V2.1: tier4 (PREMIUM+) user_type constraint

user_type CHECK kısıtına 'tier4' eklenir.

Revision ID: zzzzzzzl_tier4_user_type
Revises: zzzzzzzk_stream_minutes
Create Date: 2026-11-25
"""

from alembic import op

revision = "zzzzzzzl_tier4_user_type"
down_revision = "zzzzzzzk_stream_minutes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check")
    op.execute(
        "ALTER TABLE users ADD CONSTRAINT users_user_type_check "
        "CHECK (user_type IN ('standard', 'tier1', 'tier2', 'tier3', 'tier4'))"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check")
    op.execute(
        "ALTER TABLE users ADD CONSTRAINT users_user_type_check "
        "CHECK (user_type IN ('standard', 'tier1', 'tier2', 'tier3'))"
    )
