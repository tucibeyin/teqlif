"""stream_recordings: host_notified_at kolonu

Kayıt available olduğunda host'a bir kez bildirim gönderildiğini izler.
notify_new_recordings_task bu damgayı set eder; NULL olanlar işlenmemiş demektir.

Revision ID: zzzzzh_recording_host_notified
Revises: zzzzzg_recording_node2_confirmed
Create Date: 2026-10-09
"""
from alembic import op

revision = "zzzzzh_recording_host_notified"
down_revision = "zzzzzg_recording_node2_confirmed"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE stream_recordings "
        "ADD COLUMN IF NOT EXISTS host_notified_at TIMESTAMP WITH TIME ZONE"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE stream_recordings DROP COLUMN IF EXISTS host_notified_at"
    )
