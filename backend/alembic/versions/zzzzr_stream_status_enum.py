"""stream status explicit enum column

Revision ID: zzzzr_stream_status_enum
Revises: zzzzq_stream_viewer_analytics
Create Date: 2026-09-05
"""
from alembic import op

revision = 'zzzzr_stream_status_enum'
down_revision = 'zzzzq_stream_viewer_analytics'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE live_streams ADD COLUMN status VARCHAR(10) NOT NULL DEFAULT 'pending'"
    )
    op.execute(
        """UPDATE live_streams SET status = CASE
            WHEN ended_at IS NOT NULL THEN 'ended'
            WHEN is_live = TRUE       THEN 'live'
            ELSE                           'pending'
        END"""
    )
    op.execute(
        "CREATE INDEX ix_live_streams_status ON live_streams (status)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_live_streams_status")
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS status")
