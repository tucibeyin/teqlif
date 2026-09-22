"""feat: Float → Numeric(12,2) finansal kolonlar

Revision ID: zzzzw_float_to_numeric
Revises: zzzzv_perf_idx_v2
Create Date: 2026-09-22 02:00:00.000000
"""
from alembic import op

revision = "zzzzw_float_to_numeric"
down_revision = "zzzzv_perf_idx_v2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE listings ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
    op.execute("ALTER TABLE listings ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE listings ALTER COLUMN last_sold_price TYPE NUMERIC(12,2) USING last_sold_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE listings ALTER COLUMN last_start_price TYPE NUMERIC(12,2) USING last_start_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE auctions ALTER COLUMN start_price TYPE NUMERIC(12,2) USING start_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE auctions ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE auctions ALTER COLUMN final_price TYPE NUMERIC(12,2) USING final_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE bids ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
    op.execute("ALTER TABLE purchases ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
    op.execute("ALTER TABLE listing_offers ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
    op.execute("ALTER TABLE search_alerts ALTER COLUMN max_price TYPE NUMERIC(12,2) USING max_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE users ALTER COLUMN max_budget TYPE NUMERIC(12,2) USING max_budget::NUMERIC(12,2)")
    op.execute("ALTER TABLE direct_sales ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
    op.execute("ALTER TABLE direct_sale_orders ALTER COLUMN unit_price TYPE NUMERIC(12,2) USING unit_price::NUMERIC(12,2)")
    op.execute("ALTER TABLE exchange_rates ALTER COLUMN usd_try TYPE NUMERIC(10,4) USING usd_try::NUMERIC(10,4)")
    op.execute("ALTER TABLE exchange_rates ALTER COLUMN eur_try TYPE NUMERIC(10,4) USING eur_try::NUMERIC(10,4)")


def downgrade() -> None:
    op.execute("ALTER TABLE listings ALTER COLUMN price TYPE FLOAT USING price::FLOAT")
    op.execute("ALTER TABLE listings ALTER COLUMN buy_it_now_price TYPE FLOAT USING buy_it_now_price::FLOAT")
    op.execute("ALTER TABLE listings ALTER COLUMN last_sold_price TYPE FLOAT USING last_sold_price::FLOAT")
    op.execute("ALTER TABLE listings ALTER COLUMN last_start_price TYPE FLOAT USING last_start_price::FLOAT")
    op.execute("ALTER TABLE auctions ALTER COLUMN start_price TYPE FLOAT USING start_price::FLOAT")
    op.execute("ALTER TABLE auctions ALTER COLUMN buy_it_now_price TYPE FLOAT USING buy_it_now_price::FLOAT")
    op.execute("ALTER TABLE auctions ALTER COLUMN final_price TYPE FLOAT USING final_price::FLOAT")
    op.execute("ALTER TABLE bids ALTER COLUMN amount TYPE FLOAT USING amount::FLOAT")
    op.execute("ALTER TABLE purchases ALTER COLUMN price TYPE FLOAT USING price::FLOAT")
    op.execute("ALTER TABLE listing_offers ALTER COLUMN amount TYPE FLOAT USING amount::FLOAT")
    op.execute("ALTER TABLE search_alerts ALTER COLUMN max_price TYPE FLOAT USING max_price::FLOAT")
    op.execute("ALTER TABLE users ALTER COLUMN max_budget TYPE FLOAT USING max_budget::FLOAT")
    op.execute("ALTER TABLE direct_sales ALTER COLUMN price TYPE NUMERIC(10,2) USING price::NUMERIC(10,2)")
    op.execute("ALTER TABLE direct_sale_orders ALTER COLUMN unit_price TYPE NUMERIC(10,2) USING unit_price::NUMERIC(10,2)")
