"""create bids table

Revision ID: a9b8c7d6e5f4
Revises: 3a55d47f47f1
Create Date: 2026-03-21

"""
from alembic import op
import sqlalchemy as sa


revision = 'a9b8c7d6e5f4'
down_revision = '3a55d47f47f1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'bids',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('stream_id', sa.Integer(), sa.ForeignKey('live_streams.id'), nullable=False, index=True),
        sa.Column('bidder_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('bidder_username', sa.String(100), nullable=False),
        sa.Column('amount', sa.Float(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table('bids')
