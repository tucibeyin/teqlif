"""add is_shadowbanned to direct_messages

Revision ID: a1b2c3d4e5f6
Revises: z1a2b3c4d5e6
Create Date: 2026-06-26 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'direct_messages',
        sa.Column('is_shadowbanned', sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    # Partial index: sadece shadowbanned mesajları hızlı sorgulamak için
    op.create_index(
        'ix_dm_shadowbanned',
        'direct_messages',
        ['is_shadowbanned'],
        postgresql_where=sa.text('is_shadowbanned = true'),
    )


def downgrade() -> None:
    op.drop_index('ix_dm_shadowbanned', table_name='direct_messages')
    op.drop_column('direct_messages', 'is_shadowbanned')
