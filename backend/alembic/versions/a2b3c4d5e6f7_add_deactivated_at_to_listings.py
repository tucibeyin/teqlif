"""add deactivated_at to listings

Revision ID: a2b3c4d5e6f7
Revises: z1a2b3c4d5e6
Create Date: 2026-06-26

"""
from alembic import op
import sqlalchemy as sa

revision = 'a2b3c4d5e6f7'
down_revision = 'z1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'listings',
        sa.Column('deactivated_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        'ix_listings_deactivated_at',
        'listings',
        ['deactivated_at'],
        postgresql_where=sa.text('deactivated_at IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('ix_listings_deactivated_at', table_name='listings')
    op.drop_column('listings', 'deactivated_at')
