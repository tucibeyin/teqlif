"""stream_recordings: node2_confirmed_at kolonu

node2 MinIO backup tamamlandığında bu damga set edilir.
archive_recordings_task artık kör 4-günlük bekleme yerine
bu onayı bekler (+ 2-günlük ILM guard).

Revision ID: zzzzzg_recording_node2_confirmed
Revises: zzzzzf_dm_archive
Create Date: 2026-10-08
"""
from alembic import op

revision = "zzzzzg_recording_node2_confirmed"
down_revision = "zzzzzf_dm_archive"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE stream_recordings
            ADD COLUMN IF NOT EXISTS node2_confirmed_at TIMESTAMPTZ
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_recordings_node2_confirmed
            ON stream_recordings(node2_confirmed_at)
            WHERE node2_confirmed_at IS NULL AND status IN ('available','expired')
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stream_recordings_node2_confirmed")
    op.execute("ALTER TABLE stream_recordings DROP COLUMN IF EXISTS node2_confirmed_at")
