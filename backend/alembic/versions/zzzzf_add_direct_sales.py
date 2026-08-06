"""Add direct_sales and direct_sale_orders tables

Revision ID: zzzzf_add_direct_sales
Revises: zzzze_category_is_listable
Create Date: 2026-08-06
"""
from alembic import op

revision = 'zzzzf_add_direct_sales'
down_revision = 'zzzze_category_is_listable'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE direct_sales (
            id                    SERIAL PRIMARY KEY,
            stream_id             INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
            host_id               INTEGER NOT NULL REFERENCES users(id),
            listing_id            INTEGER REFERENCES listings(id) ON DELETE SET NULL,

            title                 VARCHAR(100) NOT NULL,
            price                 NUMERIC(10, 2) NOT NULL,
            product_image_url     VARCHAR(500),
            proof_image_url       VARCHAR(500),

            total_stock           INTEGER NOT NULL CHECK (total_stock >= 1),
            remaining_stock       INTEGER NOT NULL CHECK (remaining_stock >= 0),

            status                VARCHAR(20) NOT NULL DEFAULT 'active',
            end_reason            VARCHAR(30),
            orders_voided         BOOLEAN NOT NULL DEFAULT FALSE,

            viewer_count_at_start INTEGER,
            category              VARCHAR(50),

            started_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            ended_at              TIMESTAMP WITH TIME ZONE,

            CONSTRAINT chk_remaining_lte_total CHECK (remaining_stock <= total_stock),
            CONSTRAINT chk_end_reason CHECK (
                end_reason IN ('sold_out', 'host_ended', 'stream_closed') OR end_reason IS NULL
            ),
            CONSTRAINT chk_direct_sale_status CHECK (
                status IN ('active', 'paused', 'sold_out', 'ended', 'cancelled')
            )
        )
    """)
    op.execute("CREATE INDEX ix_direct_sales_stream_id ON direct_sales(stream_id)")
    op.execute("CREATE INDEX ix_direct_sales_host_id   ON direct_sales(host_id)")
    op.execute("CREATE INDEX ix_direct_sales_status    ON direct_sales(status)")

    op.execute("""
        CREATE TABLE direct_sale_orders (
            id         SERIAL PRIMARY KEY,
            sale_id    INTEGER NOT NULL REFERENCES direct_sales(id) ON DELETE CASCADE,
            seller_id  INTEGER NOT NULL REFERENCES users(id),
            buyer_id   INTEGER NOT NULL REFERENCES users(id),
            listing_id INTEGER REFERENCES listings(id) ON DELETE SET NULL,
            quantity   INTEGER NOT NULL CHECK (quantity >= 1),
            unit_price NUMERIC(10, 2) NOT NULL,
            status     VARCHAR(20) NOT NULL DEFAULT 'completed',
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

            CONSTRAINT chk_direct_sale_order_status CHECK (
                status IN ('completed', 'cancelled')
            )
        )
    """)
    op.execute("CREATE INDEX ix_direct_sale_orders_sale_id   ON direct_sale_orders(sale_id)")
    op.execute("CREATE INDEX ix_direct_sale_orders_buyer_id  ON direct_sale_orders(buyer_id)")
    op.execute("CREATE INDEX ix_direct_sale_orders_seller_id ON direct_sale_orders(seller_id)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS direct_sale_orders")
    op.execute("DROP TABLE IF EXISTS direct_sales")
