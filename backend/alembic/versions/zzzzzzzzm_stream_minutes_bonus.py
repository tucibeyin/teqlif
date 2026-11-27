"""wallet V1.2: users.stream_minutes_bonus

Teqlik ile satın alınan bonus yayın dakikaları.
Aylık reset'e dahil değil — kullanıcı teqlik ödemişse dakika kalıcıdır.

Revision ID: zzzzzzzzm_stream_minutes_bonus
Revises: zzzzzzzl_tier4_user_type
Create Date: 2026-11-28
"""

from alembic import op
import sqlalchemy as sa

revision = "zzzzzzzzm_stream_minutes_bonus"
down_revision = "zzzzzzzl_tier4_user_type"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users",
        sa.Column(
            "stream_minutes_bonus",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade():
    op.drop_column("users", "stream_minutes_bonus")
