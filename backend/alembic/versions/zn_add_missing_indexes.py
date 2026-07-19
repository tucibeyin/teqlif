"""Add missing indexes for hot query paths

Revision ID: zn_add_missing_indexes
Revises: zm_drop_e2ee_key
Create Date: 2026-07-19
"""
from alembic import op

revision = "zn_add_missing_indexes"
down_revision = "zm_drop_e2ee_key"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # auctions: winner lookup and listing-to-auction join
    op.create_index("ix_auctions_winner_id", "auctions", ["winner_id"])
    op.create_index("ix_auctions_listing_id", "auctions", ["listing_id"])

    # notifications: fast unread-count per user
    op.create_index("ix_notifications_user_is_read", "notifications", ["user_id", "is_read"])

    # direct_messages: unread count for inbox badge
    op.create_index("ix_dm_receiver_is_read", "direct_messages", ["receiver_id", "is_read"])

    # calls: active/missed call lookup by participant
    op.create_index("ix_calls_caller_status", "calls", ["caller_id", "status"])
    op.create_index("ix_calls_callee_status", "calls", ["callee_id", "status"])

    # live_streams: discover live streams sorted by recency
    op.create_index("ix_live_streams_is_live_started_at", "live_streams", ["is_live", "started_at"])


def downgrade() -> None:
    op.drop_index("ix_live_streams_is_live_started_at", table_name="live_streams")
    op.drop_index("ix_calls_callee_status", table_name="calls")
    op.drop_index("ix_calls_caller_status", table_name="calls")
    op.drop_index("ix_dm_receiver_is_read", table_name="direct_messages")
    op.drop_index("ix_notifications_user_is_read", table_name="notifications")
    op.drop_index("ix_auctions_listing_id", table_name="auctions")
    op.drop_index("ix_auctions_winner_id", table_name="auctions")
