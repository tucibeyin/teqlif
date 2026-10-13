"""stream_chat_messages: chat replay tablosu

Revision ID: zzzzzo_stream_chat_messages
Revises: zzzzzn_recording_egress
Create Date: 2026-10-13
"""
from alembic import op

revision = "zzzzzo_stream_chat_messages"
down_revision = "zzzzzn_recording_egress"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS stream_chat_messages (
            id          BIGSERIAL PRIMARY KEY,
            stream_id   INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
            user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
            username    VARCHAR(100) NOT NULL,
            avatar_url  TEXT,
            content     TEXT NOT NULL,
            is_host     BOOLEAN NOT NULL DEFAULT FALSE,
            is_mod      BOOLEAN NOT NULL DEFAULT FALSE,
            is_hidden   BOOLEAN NOT NULL DEFAULT FALSE,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_chat_messages_stream_id
            ON stream_chat_messages (stream_id, created_at)
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS stream_chat_messages CASCADE")
