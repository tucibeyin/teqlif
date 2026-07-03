"""final merge all heads

Revision ID: b1c2d3e4f5a6
Revises: a2b3c4d5e7f8, 265342ad935a
Create Date: 2026-07-03 12:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b1c2d3e4f5a6'
down_revision: Union[str, Sequence[str], None] = ('a2b3c4d5e7f8', '265342ad935a')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
