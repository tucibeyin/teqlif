"""Add calls table for voice calling feature

Revision ID: zc_add_calls_table
Revises: zb_merge_gift_and_media
Create Date: 2026-07-12
"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "zc_add_calls_table"
down_revision: Union[str, Sequence[str], None] = "zb_merge_gift_and_media"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "calls",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("caller_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("callee_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("room_name", sa.String(100), nullable=False, unique=True),
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="calling",
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_calls_caller_id", "calls", ["caller_id"])
    op.create_index("ix_calls_callee_id", "calls", ["callee_id"])
    op.create_index("ix_calls_started_at", "calls", ["started_at"])


def downgrade() -> None:
    op.drop_table("calls")
