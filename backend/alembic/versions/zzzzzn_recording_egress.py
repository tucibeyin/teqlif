"""stream_recordings: egress_id kolonu (livekit-egress entegrasyonu)

Revision ID: zzzzzn_recording_egress
Revises: zzzzzm_drop_image_phash
Create Date: 2026-10-12
"""
from alembic import op

revision = "zzzzzn_recording_egress"
down_revision = "zzzzzm_drop_image_phash"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE stream_recordings
            ADD COLUMN IF NOT EXISTS egress_id TEXT
    """)


def downgrade() -> None:
    op.execute("ALTER TABLE stream_recordings DROP COLUMN IF EXISTS egress_id")
