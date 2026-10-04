"""stream_recordings tablosu ve live_streams.recording_enabled

Revision ID: zzzzzb_stream_recordings
Revises: zzzzza_tuci_column_renames
Create Date: 2026-10-04
"""
from alembic import op

revision = "zzzzzb_stream_recordings"
down_revision = "zzzzza_tuci_column_renames"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE live_streams
            ADD COLUMN IF NOT EXISTS recording_enabled BOOLEAN NOT NULL DEFAULT FALSE
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS stream_recordings (
            id                    BIGSERIAL PRIMARY KEY,
            stream_id             INTEGER NOT NULL REFERENCES live_streams(id),
            host_id               INTEGER NOT NULL REFERENCES users(id),
            status                VARCHAR(20) NOT NULL DEFAULT 'recording',
            recording_node        VARCHAR(10),
            raw_path              TEXT,
            encoded_path          TEXT,
            minio_key             TEXT,
            raw_size_bytes        BIGINT,
            encoded_size_bytes    BIGINT,
            duration_secs         INTEGER,
            recording_started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            encoding_started_at   TIMESTAMPTZ,
            encoded_at            TIMESTAMPTZ,
            transferred_at        TIMESTAMPTZ,
            available_at          TIMESTAMPTZ,
            expires_at            TIMESTAMPTZ,
            archived_at           TIMESTAMPTZ,
            deleted_at            TIMESTAMPTZ,
            notified_at           TIMESTAMPTZ,
            error_message         TEXT,
            retry_count           INTEGER NOT NULL DEFAULT 0,
            created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_recordings_stream_id
            ON stream_recordings(stream_id)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_recordings_host_id
            ON stream_recordings(host_id)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_recordings_status
            ON stream_recordings(status)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_stream_recordings_expires_at
            ON stream_recordings(expires_at)
            WHERE status = 'available'
    """)

    op.execute("""
        GRANT SELECT, INSERT, UPDATE ON stream_recordings TO teqlif_agent
    """)

    op.execute("""
        GRANT USAGE, SELECT ON SEQUENCE stream_recordings_id_seq TO teqlif_agent
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS stream_recordings")
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS recording_enabled")
