"""add duration_seconds to calls

Revision ID: zj_add_call_duration_seconds
Revises: zi_add_accepted_at_to_calls
Create Date: 2026-07-14

"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "zj_add_call_duration_seconds"
down_revision: Union[str, Sequence[str], None] = "zi_add_accepted_at_to_calls"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "calls",
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("calls", "duration_seconds")
