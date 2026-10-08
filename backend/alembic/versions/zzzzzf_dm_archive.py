"""DM arşiv: message_threads.has_archive kolonu

Revision ID: zzzzzf_dm_archive
Revises: zzzzze_recording_v13
Create Date: 2026-10-08
"""
from alembic import op

revision = "zzzzzf_dm_archive"
down_revision = "zzzzze_recording_v13"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE message_threads
            ADD COLUMN IF NOT EXISTS has_archive BOOLEAN NOT NULL DEFAULT FALSE
    """)


def downgrade() -> None:
    op.execute("""
        ALTER TABLE message_threads
            DROP COLUMN IF EXISTS has_archive
    """)
