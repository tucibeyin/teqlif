"""add listing_id to direct_messages

Revision ID: d5e6f7a8b9c0
Revises: c5d6e7f8a9b0
Create Date: 2026-07-02 00:02:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'd5e6f7a8b9c0'
down_revision = 'c5d6e7f8a9b0'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('direct_messages',
        sa.Column('listing_id', sa.Integer(), nullable=True)
    )
    op.create_foreign_key(
        'fk_direct_messages_listing_id',
        'direct_messages', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL'
    )
    op.create_index('ix_direct_messages_listing_id', 'direct_messages', ['listing_id'])


def downgrade():
    op.drop_index('ix_direct_messages_listing_id', table_name='direct_messages')
    op.drop_constraint('fk_direct_messages_listing_id', 'direct_messages', type_='foreignkey')
    op.drop_column('direct_messages', 'listing_id')
