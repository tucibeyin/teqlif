"""add voip_token

Revision ID: zf_add_voip_token
Revises: ze_fix_follow_status
Create Date: 2026-07-13

"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "zf_add_voip_token"
down_revision: Union[str, Sequence[str], None] = "ze_fix_follow_status"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('voip_token', sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'voip_token')
