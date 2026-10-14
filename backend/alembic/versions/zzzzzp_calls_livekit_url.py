"""calls_livekit_url: store livekit_url on call creation to prevent multi-node split

Revision ID: zzzzzp_calls_livekit_url
Revises: zzzzzo_stream_chat_messages
Create Date: 2026-10-15
"""
from alembic import op
import sqlalchemy as sa

revision = "zzzzzp_calls_livekit_url"
down_revision = "zzzzzo_stream_chat_messages"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "ALTER TABLE calls ADD COLUMN IF NOT EXISTS livekit_url VARCHAR(300)"
    )


def downgrade():
    op.execute("ALTER TABLE calls DROP COLUMN IF EXISTS livekit_url")
