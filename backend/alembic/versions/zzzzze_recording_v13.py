"""V1.3: recording_enabled kaldır, Bid.auction_id ekle

Revision ID: zzzzze_recording_v13
Revises: zzzzzd_analytics_type_created
Create Date: 2026-10-08
"""
from alembic import op

revision = "zzzzze_recording_v13"
down_revision = "zzzzzd_analytics_type_created"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. live_streams.recording_enabled kaldır
    #    Artık zorunlu kayıt — tüm yayınlar kaydedilir; PRO flag kontrol eder.
    op.execute("""
        ALTER TABLE live_streams
            DROP COLUMN IF EXISTS recording_enabled
    """)

    # 2. bids.auction_id ekle — teklifleri müzayede bazında gruplamak için
    op.execute("""
        ALTER TABLE bids
            ADD COLUMN IF NOT EXISTS auction_id INTEGER REFERENCES auctions(id) ON DELETE SET NULL
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_bids_auction_id
            ON bids(auction_id)
            WHERE auction_id IS NOT NULL
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_bids_auction_id")
    op.execute("ALTER TABLE bids DROP COLUMN IF EXISTS auction_id")
    op.execute("""
        ALTER TABLE live_streams
            ADD COLUMN IF NOT EXISTS recording_enabled BOOLEAN NOT NULL DEFAULT FALSE
    """)
