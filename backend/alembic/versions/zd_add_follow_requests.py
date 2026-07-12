"""Add follow status and user is_private

Revision ID: zd_add_follow_requests
Revises: zc_add_calls_table
Create Date: 2026-07-12
"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "zd_add_follow_requests"
down_revision: Union[str, Sequence[str], None] = "zc_add_calls_table"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("is_private", sa.Boolean(), server_default="false", nullable=False))
    op.add_column("follows", sa.Column("status", sa.String(length=20), server_default="'accepted'", nullable=False))


def downgrade() -> None:
    op.drop_column("follows", "status")
    op.drop_column("users", "is_private")
