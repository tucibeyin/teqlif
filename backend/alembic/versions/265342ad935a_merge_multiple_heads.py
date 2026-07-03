"""merge multiple heads

Revision ID: 265342ad935a
Revises: a3b4c5d6e7f8, caabfa5344f9
Create Date: 2026-06-29 18:37:05.465588

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '265342ad935a'
down_revision: Union[str, Sequence[str], None] = ('a3b4c5d6e7f8', 'caabfa5344f9')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
