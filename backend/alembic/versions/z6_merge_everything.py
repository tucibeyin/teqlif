"""Merge everything

Revision ID: z6_merge_everything
Revises: z5_add_locale, merge20260706_all_heads
Create Date: 2026-07-06 20:59:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'z6_merge_everything'
down_revision: Union[str, Sequence[str], None] = ('z5_add_locale', 'merge20260706_all_heads')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
