"""stream viewer analytics: left_at + peak_viewer_count

Revision ID: zzzzq_stream_viewer_analytics
Revises: zzzzp_delete_soft
Create Date: 2026-09-05
"""
from alembic import op

revision = 'zzzzq_stream_viewer_analytics'
down_revision = 'zzzzp_delete_soft'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE live_stream_viewers ADD COLUMN left_at TIMESTAMP WITH TIME ZONE"
    )
    op.execute(
        "CREATE INDEX ix_live_stream_viewers_left_at ON live_stream_viewers (left_at)"
    )
    op.execute(
        "ALTER TABLE live_streams ADD COLUMN peak_viewer_count INTEGER"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_live_stream_viewers_left_at")
    op.execute("ALTER TABLE live_stream_viewers DROP COLUMN IF EXISTS left_at")
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS peak_viewer_count")
