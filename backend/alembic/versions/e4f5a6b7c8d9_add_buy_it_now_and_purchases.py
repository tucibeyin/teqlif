"""add buy_it_now and purchases table

Revision ID: e4f5a6b7c8d9
Revises: b2c3d4e5f6a7
Create Date: 2026-03-22

"""
from alembic import op
import sqlalchemy as sa

revision = 'e4f5a6b7c8d9'
down_revision = 'b2c3d4e5f6a7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # listings.buy_it_now_price
    op.add_column('listings',
        sa.Column('buy_it_now_price', sa.Float(), nullable=True))

    # auctions.buy_it_now_price
    op.add_column('auctions',
        sa.Column('buy_it_now_price', sa.Float(), nullable=True))

    # auctions.is_bought_it_now
    op.add_column('auctions',
        sa.Column('is_bought_it_now', sa.Boolean(), nullable=False,
                  server_default=sa.text('false')))

    # purchases tablosu
    op.create_table(
        'purchases',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('buyer_id', sa.Integer(),
                  sa.ForeignKey('users.id'), nullable=False),
        sa.Column('listing_id', sa.Integer(),
                  sa.ForeignKey('listings.id'), nullable=True),
        sa.Column('auction_id', sa.Integer(),
                  sa.ForeignKey('auctions.id'), nullable=True),
        sa.Column('price', sa.Float(), nullable=False),
        sa.Column('purchase_type', sa.String(20), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.func.now()),
    )
    op.create_index('ix_purchases_buyer_id', 'purchases', ['buyer_id'])
    op.create_index('ix_purchases_listing_id', 'purchases', ['listing_id'])
    op.create_index('ix_purchases_auction_id', 'purchases', ['auction_id'])


def downgrade() -> None:
    op.drop_index('ix_purchases_auction_id', table_name='purchases')
    op.drop_index('ix_purchases_listing_id', table_name='purchases')
    op.drop_index('ix_purchases_buyer_id', table_name='purchases')
    op.drop_table('purchases')
    op.drop_column('auctions', 'is_bought_it_now')
    op.drop_column('auctions', 'buy_it_now_price')
    op.drop_column('listings', 'buy_it_now_price')
