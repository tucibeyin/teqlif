"""users.last_active_at — ForYou hayalet kullanıcı filtresi (SRE-05)

Revision ID: zzzzzzc_users_last_activ
Revises: zzzzzzb_users_follower_co
Create Date: 2026-11-01
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzzc_users_last_activ"
down_revision = "zzzzzzb_users_follower_co"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "last_active_at")
