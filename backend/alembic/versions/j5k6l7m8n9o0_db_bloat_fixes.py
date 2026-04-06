"""db_bloat_fixes: cascade fk + composite indexes

Revision ID: j5k6l7m8n9o0
Revises: i4j5k6l7m8n9
Create Date: 2026-04-06

Değişiklikler:
  1. favorites.user_id    → ON DELETE CASCADE  (kullanıcı silinince favoriler de silinir)
  2. favorites.listing_id → ON DELETE CASCADE  (listing hard-delete edilince favoriler de silinir)
  3. listing_offers.user_id    → ON DELETE CASCADE
  4. listing_offers.listing_id → ON DELETE CASCADE
  5. notifications(user_id, created_at)               composite index
  6. direct_messages(sender_id, receiver_id, created_at) composite index
  7. analytics_events(user_id, created_at)            composite index
  8. stream_likes(stream_id, created_at)              composite index — cleanup cron için
"""
from typing import Sequence, Union
from alembic import op

revision: str = 'j5k6l7m8n9o0'
down_revision: Union[str, Sequence[str], None] = 'i4j5k6l7m8n9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1-2. favorites FK'larını CASCADE'e yükselt ────────────────────────────
    op.execute("""
        ALTER TABLE favorites
            DROP CONSTRAINT IF EXISTS favorites_user_id_fkey,
            ADD CONSTRAINT favorites_user_id_fkey
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
    """)
    op.execute("""
        ALTER TABLE favorites
            DROP CONSTRAINT IF EXISTS favorites_listing_id_fkey,
            ADD CONSTRAINT favorites_listing_id_fkey
                FOREIGN KEY (listing_id) REFERENCES listings(id) ON DELETE CASCADE;
    """)

    # ── 3-4. listing_offers FK'larını CASCADE'e yükselt ─────────────────────
    op.execute("""
        ALTER TABLE listing_offers
            DROP CONSTRAINT IF EXISTS listing_offers_user_id_fkey,
            ADD CONSTRAINT listing_offers_user_id_fkey
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
    """)
    op.execute("""
        ALTER TABLE listing_offers
            DROP CONSTRAINT IF EXISTS listing_offers_listing_id_fkey,
            ADD CONSTRAINT listing_offers_listing_id_fkey
                FOREIGN KEY (listing_id) REFERENCES listings(id) ON DELETE CASCADE;
    """)

    # ── 5. notifications composite index ──────────────────────────────────────
    op.create_index(
        'ix_notifications_user_created',
        'notifications',
        ['user_id', 'created_at'],
    )

    # ── 6. direct_messages composite index ────────────────────────────────────
    op.create_index(
        'ix_direct_messages_conv_created',
        'direct_messages',
        ['sender_id', 'receiver_id', 'created_at'],
    )

    # ── 7. analytics_events composite index ───────────────────────────────────
    op.create_index(
        'ix_analytics_events_user_created',
        'analytics_events',
        ['user_id', 'created_at'],
    )

    # ── 8. stream_likes composite index ───────────────────────────────────────
    op.create_index(
        'ix_stream_likes_stream_created',
        'stream_likes',
        ['stream_id', 'created_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_stream_likes_stream_created', table_name='stream_likes')
    op.drop_index('ix_analytics_events_user_created', table_name='analytics_events')
    op.drop_index('ix_direct_messages_conv_created', table_name='direct_messages')
    op.drop_index('ix_notifications_user_created', table_name='notifications')

    # listing_offers CASCADE → RESTRICT (default)
    op.execute("""
        ALTER TABLE listing_offers
            DROP CONSTRAINT IF EXISTS listing_offers_listing_id_fkey,
            ADD CONSTRAINT listing_offers_listing_id_fkey
                FOREIGN KEY (listing_id) REFERENCES listings(id);
    """)
    op.execute("""
        ALTER TABLE listing_offers
            DROP CONSTRAINT IF EXISTS listing_offers_user_id_fkey,
            ADD CONSTRAINT listing_offers_user_id_fkey
                FOREIGN KEY (user_id) REFERENCES users(id);
    """)

    # favorites CASCADE → RESTRICT (default)
    op.execute("""
        ALTER TABLE favorites
            DROP CONSTRAINT IF EXISTS favorites_listing_id_fkey,
            ADD CONSTRAINT favorites_listing_id_fkey
                FOREIGN KEY (listing_id) REFERENCES listings(id);
    """)
    op.execute("""
        ALTER TABLE favorites
            DROP CONSTRAINT IF EXISTS favorites_user_id_fkey,
            ADD CONSTRAINT favorites_user_id_fkey
                FOREIGN KEY (user_id) REFERENCES users(id);
    """)
