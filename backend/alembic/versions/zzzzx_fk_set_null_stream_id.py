"""fix: FK SET NULL — gift_events/bids/direct_sales/auctions → stream_id

Revision ID: zzzzx_fk_set_null_stream_id
Revises: zzzzw_float_to_numeric
Create Date: 2026-09-22 10:00:00.000000
"""
from alembic import op

revision = "zzzzx_fk_set_null_stream_id"
down_revision = "zzzzw_float_to_numeric"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # gift_events.stream_id: CASCADE → SET NULL + nullable
    op.execute("ALTER TABLE gift_events DROP CONSTRAINT gift_events_stream_id_fkey")
    op.execute("ALTER TABLE gift_events ALTER COLUMN stream_id DROP NOT NULL")
    op.execute(
        "ALTER TABLE gift_events ADD CONSTRAINT gift_events_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL"
    )

    # bids.stream_id: (tanımsız) → SET NULL + nullable
    op.execute("ALTER TABLE bids DROP CONSTRAINT IF EXISTS bids_stream_id_fkey")
    op.execute("ALTER TABLE bids ALTER COLUMN stream_id DROP NOT NULL")
    op.execute(
        "ALTER TABLE bids ADD CONSTRAINT bids_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL"
    )

    # direct_sales.stream_id: CASCADE → SET NULL + nullable
    op.execute("ALTER TABLE direct_sales DROP CONSTRAINT direct_sales_stream_id_fkey")
    op.execute("ALTER TABLE direct_sales ALTER COLUMN stream_id DROP NOT NULL")
    op.execute(
        "ALTER TABLE direct_sales ADD CONSTRAINT direct_sales_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL"
    )

    # auctions.stream_id: (tanımsız) → SET NULL + nullable
    op.execute("ALTER TABLE auctions DROP CONSTRAINT IF EXISTS auctions_stream_id_fkey")
    op.execute("ALTER TABLE auctions ALTER COLUMN stream_id DROP NOT NULL")
    op.execute(
        "ALTER TABLE auctions ADD CONSTRAINT auctions_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE gift_events DROP CONSTRAINT gift_events_stream_id_fkey")
    op.execute("ALTER TABLE gift_events ALTER COLUMN stream_id SET NOT NULL")
    op.execute(
        "ALTER TABLE gift_events ADD CONSTRAINT gift_events_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE"
    )

    op.execute("ALTER TABLE bids DROP CONSTRAINT IF EXISTS bids_stream_id_fkey")
    op.execute("ALTER TABLE bids ALTER COLUMN stream_id SET NOT NULL")
    op.execute(
        "ALTER TABLE bids ADD CONSTRAINT bids_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id)"
    )

    op.execute("ALTER TABLE direct_sales DROP CONSTRAINT direct_sales_stream_id_fkey")
    op.execute("ALTER TABLE direct_sales ALTER COLUMN stream_id SET NOT NULL")
    op.execute(
        "ALTER TABLE direct_sales ADD CONSTRAINT direct_sales_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE"
    )

    op.execute("ALTER TABLE auctions DROP CONSTRAINT IF EXISTS auctions_stream_id_fkey")
    op.execute("ALTER TABLE auctions ALTER COLUMN stream_id SET NOT NULL")
    op.execute(
        "ALTER TABLE auctions ADD CONSTRAINT auctions_stream_id_fkey "
        "FOREIGN KEY (stream_id) REFERENCES live_streams(id)"
    )
