"""add e2ee_key to calls

Revision ID: zl_add_e2ee_key
Revises: zk_call_compound_indexes
Create Date: 2026-07-16
"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "zl_add_e2ee_key"
down_revision: Union[str, Sequence[str], None] = "zk_call_compound_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "calls",
        sa.Column("e2ee_key", sa.String(64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("calls", "e2ee_key")
