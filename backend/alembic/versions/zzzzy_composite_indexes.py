"""perf: composite index'ler — tuci_transactions/purchases/user_interactions/listings

Revision ID: zzzzy_composite_indexes
Revises: zzzzx_fk_set_null_stream_id
Create Date: 2026-09-22 12:00:00.000000
"""
from alembic import op

revision = "zzzzy_composite_indexes"
down_revision = "zzzzx_fk_set_null_stream_id"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE INDEX ix_tuci_transactions_user_created ON tuci_transactions (user_id, created_at DESC)")
    op.execute("CREATE INDEX ix_purchases_buyer_created ON purchases (buyer_id, created_at DESC)")
    op.execute("CREATE INDEX ix_user_interactions_user_created ON user_interactions (user_id, created_at)")
    op.execute("CREATE INDEX ix_listings_user_status ON listings (user_id, status)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_tuci_transactions_user_created")
    op.execute("DROP INDEX IF EXISTS ix_purchases_buyer_created")
    op.execute("DROP INDEX IF EXISTS ix_user_interactions_user_created")
    op.execute("DROP INDEX IF EXISTS ix_listings_user_status")
