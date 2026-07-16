"""drop e2ee_key from calls

Revision ID: zm_drop_e2ee_key
Revises: zl_add_e2ee_key
Create Date: 2026-07-17
"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "zm_drop_e2ee_key"
down_revision: Union[str, Sequence[str], None] = "zl_add_e2ee_key"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("calls", "e2ee_key")


def downgrade() -> None:
    op.add_column(
        "calls",
        sa.Column("e2ee_key", sa.String(64), nullable=True),
    )
