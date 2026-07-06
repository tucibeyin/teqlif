"""enable pg_trgm extension

Revision ID: 20260706_pgtrgm
Revises: a1b2c3d4e5
Create Date: 2026-07-06 15:52:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20260706_pgtrgm'
down_revision: Union[str, None] = 'a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable pg_trgm extension for advanced text searching
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")


def downgrade() -> None:
    # Disable pg_trgm extension
    op.execute("DROP EXTENSION IF EXISTS pg_trgm;")
