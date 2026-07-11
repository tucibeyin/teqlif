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
    op.create_table(
        "gift_events",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column(
            "stream_id",
            sa.Integer,
            sa.ForeignKey("live_streams.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "sender_id",
            sa.Integer,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "receiver_id",
            sa.Integer,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("gift_name", sa.String(50), nullable=False),
        sa.Column("cost_tuci", sa.Integer, nullable=False),
        sa.Column("host_share", sa.Integer, nullable=False),
        sa.Column(
            "sent_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_gift_events_stream", "gift_events", ["stream_id", "sent_at"])
    op.create_index("ix_gift_events_sender", "gift_events", ["sender_id"])
    op.create_index("ix_gift_events_receiver", "gift_events", ["receiver_id"])


def downgrade() -> None:
    op.drop_index("ix_gift_events_receiver", table_name="gift_events")
    op.drop_index("ix_gift_events_sender", table_name="gift_events")
    op.drop_index("ix_gift_events_stream", table_name="gift_events")
    op.drop_table("gift_events")
