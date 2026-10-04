"""teqlif_agent için live_streams SELECT yetkisi

Revision ID: zzzzzc_agent_streams_grant
Revises: zzzzzb_stream_recordings
Create Date: 2026-10-04
"""
from alembic import op

revision = "zzzzzc_agent_streams_grant"
down_revision = "zzzzzb_stream_recordings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("GRANT SELECT ON live_streams TO teqlif_agent")


def downgrade() -> None:
    op.execute("REVOKE SELECT ON live_streams FROM teqlif_agent")
