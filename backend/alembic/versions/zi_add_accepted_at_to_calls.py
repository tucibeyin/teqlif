"""add accepted_at to calls

Revision ID: zi_add_accepted_at_to_calls
Revises: zh_add_voip_token_updated_at
Create Date: 2026-07-13

"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "zi_add_accepted_at_to_calls"
down_revision: Union[str, Sequence[str], None] = "zh_add_voip_token_updated_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'calls',
        sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('calls', 'accepted_at')
