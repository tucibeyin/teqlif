"""users.follower_count denormalize sütunu (SRE-79)

Revision ID: zzzzzzb_users_follower_co
Revises: zzzzzza_referral_unique
Create Date: 2026-10-31
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzzb_users_follower_co"
down_revision = "zzzzzza_referral_unique"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("follower_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.execute(
        "UPDATE users SET follower_count = ("
        "    SELECT COUNT(*) FROM follows WHERE followed_id = users.id"
        ")"
    )


def downgrade() -> None:
    op.drop_column("users", "follower_count")
