"""add voip_token_updated_at to users

Revision ID: zh_add_voip_token_updated_at
Revises: zg_add_is_read_to_ratings
Create Date: 2026-07-13

"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "zh_add_voip_token_updated_at"
down_revision: Union[str, Sequence[str], None] = "zg_add_is_read_to_ratings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('voip_token_updated_at', sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('users', 'voip_token_updated_at')
