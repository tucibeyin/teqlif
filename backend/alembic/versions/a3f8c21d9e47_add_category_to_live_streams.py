"""add_category_to_live_streams

Revision ID: a3f8c21d9e47
Revises: dddf1a14c4eb
Create Date: 2026-03-14 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a3f8c21d9e47'
down_revision: Union[str, Sequence[str], None] = 'dddf1a14c4eb'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'live_streams',
        sa.Column('category', sa.String(length=60), nullable=False, server_default='diger'),
    )


def downgrade() -> None:
    op.drop_column('live_streams', 'category')
