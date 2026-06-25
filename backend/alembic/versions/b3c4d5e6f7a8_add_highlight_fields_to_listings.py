"""add highlight fields to listings

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-06-26

"""
from alembic import op
import sqlalchemy as sa

revision = 'b3c4d5e6f7a8'
down_revision = 'a2b3c4d5e6f7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('listings', sa.Column('is_highlight', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('listings', sa.Column('active_room_id', sa.Integer(), nullable=True))
    op.add_column('listings', sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index('ix_listings_active_room_id', 'listings', ['active_room_id'])


def downgrade() -> None:
    op.drop_index('ix_listings_active_room_id', table_name='listings')
    op.drop_column('listings', 'expires_at')
    op.drop_column('listings', 'active_room_id')
    op.drop_column('listings', 'is_highlight')
