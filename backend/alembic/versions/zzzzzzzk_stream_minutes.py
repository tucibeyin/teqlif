"""stream: seconds → minutes (ceil yuvarlama)

monthly_stream_seconds_used → monthly_stream_minutes_used
Mevcut veriler: CEIL(seconds / 60.0) ile dönüştürülür.

Revision ID: zzzzzzzk_stream_minutes
Revises: zzzzzzzj_subscription_v2
Create Date: 2026-11-25
"""

from alembic import op
import sqlalchemy as sa

revision = "zzzzzzzk_stream_minutes"
down_revision = "zzzzzzzj_subscription_v2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column(
        "monthly_stream_minutes_used",
        sa.Integer(),
        nullable=False,
        server_default="0",
    ))
    op.execute(
        "UPDATE users SET monthly_stream_minutes_used = "
        "CEIL(COALESCE(monthly_stream_seconds_used, 0) / 60.0)::INTEGER"
    )
    op.drop_column("users", "monthly_stream_seconds_used")


def downgrade() -> None:
    op.add_column("users", sa.Column(
        "monthly_stream_seconds_used",
        sa.Integer(),
        nullable=False,
        server_default="0",
    ))
    op.execute(
        "UPDATE users SET monthly_stream_seconds_used = monthly_stream_minutes_used * 60"
    )
    op.drop_column("users", "monthly_stream_minutes_used")
