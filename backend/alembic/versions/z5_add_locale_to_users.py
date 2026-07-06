"""Add locale to users

Revision ID: z5_add_locale
Revises: merge20260706_final
Create Date: 2026-07-06 20:55:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'z5_add_locale'
down_revision: Union[str, Sequence[str], None] = 'merge20260706_final'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add locale column
    op.add_column('users', sa.Column('locale', sa.String(length=10), server_default='tr', nullable=False))


def downgrade() -> None:
    op.drop_column('users', 'locale')
