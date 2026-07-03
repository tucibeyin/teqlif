"""merge_heads

Revision ID: caabfa5344f9
Revises: 9f8e7d6c5b4a, f7e8d9c0b1a2, z2a3b4c5d6e7
Create Date: 2026-06-28 11:03:44.002508

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'caabfa5344f9'
down_revision: Union[str, Sequence[str], None] = ('9f8e7d6c5b4a', 'f7e8d9c0b1a2', 'z2a3b4c5d6e7')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
