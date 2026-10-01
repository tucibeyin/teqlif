"""add gift_events table

Revision ID: z10_add_gift_events
Revises: z9_add_txn_reference
Create Date: 2026-07-11

Event-driven hediye mimarisi:
- gift_events tablosu: sender, receiver, gift_name, cost_tuci, host_share, stream_id
- TuciTransaction.reference_type = "gift_event" → GiftEvent.id
- Redis gift:log:{stream_id} listesi uygulama tarafında yönetilir (migration gerekmez)
"""

from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "z10_add_gift_events"
down_revision: Union[str, Sequence[str], None] = "z9_add_txn_reference"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS gift_events (
            id         SERIAL PRIMARY KEY,
            stream_id  INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
            sender_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            receiver_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            gift_name  VARCHAR(50) NOT NULL,
            cost_tuci  INTEGER NOT NULL,
            host_share INTEGER NOT NULL,
            sent_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_gift_events_stream   ON gift_events (stream_id, sent_at)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_gift_events_sender   ON gift_events (sender_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_gift_events_receiver ON gift_events (receiver_id)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_gift_events_receiver")
    op.execute("DROP INDEX IF EXISTS ix_gift_events_sender")
    op.execute("DROP INDEX IF EXISTS ix_gift_events_stream")
    op.execute("DROP TABLE IF EXISTS gift_events")
