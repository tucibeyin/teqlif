"""merge heads: db_bloat_fixes + shadowban_automod

Revision ID: k6l7m8n9o0p1
Revises: 77d110fe1803, j5k6l7m8n9o0
Create Date: 2026-04-06

"""
from typing import Sequence, Union

from alembic import op

revision: str = 'k6l7m8n9o0p1'
down_revision: Union[str, Sequence[str]] = ('77d110fe1803', 'j5k6l7m8n9o0')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
