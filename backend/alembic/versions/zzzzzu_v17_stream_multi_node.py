"""V1.7 multi-node stream: source_node_id, is_concat_result, part_number

Revision ID: zzzzzu_v17_stream_multi_node
Revises: zzzzzt_agent_select_grant
Create Date: 2026-10-22
"""
from alembic import op

revision = "zzzzzu_v17_stream_multi_node"
down_revision = "zzzzzt_agent_select_grant"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # live_streams: failover sırasında hangi node'da yayın yapıldığını takip eder
    op.execute("""
        ALTER TABLE live_streams
            ADD COLUMN IF NOT EXISTS source_node_id VARCHAR(50)
    """)

    # stream_recordings: concat sonucu satırları ayırt etmek ve bölüm numarası için
    op.execute("""
        ALTER TABLE stream_recordings
            ADD COLUMN IF NOT EXISTS is_concat_result BOOLEAN NOT NULL DEFAULT FALSE,
            ADD COLUMN IF NOT EXISTS part_number SMALLINT
    """)

    # stream_recordings: merged_and_purged durumu — part satırları concat sonrası bu duruma alınır
    # Mevcut status sütunu VARCHAR(20) ve CHECK kısıtı yoktu; yalnızca agent grant gerekiyor
    op.execute("""
        GRANT DELETE ON stream_recordings TO teqlif_agent
    """)


def downgrade() -> None:
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS source_node_id")
    op.execute("ALTER TABLE stream_recordings DROP COLUMN IF EXISTS is_concat_result")
    op.execute("ALTER TABLE stream_recordings DROP COLUMN IF EXISTS part_number")
