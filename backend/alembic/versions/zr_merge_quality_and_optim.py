"""Merge zq_add_quality_score and optim_ai_price heads into single branch

Revision ID: zr_merge_quality_and_optim
Revises: zq_add_quality_score, optim_ai_price
Create Date: 2026-07-22
"""
from alembic import op
import sqlalchemy as sa
from typing import Sequence, Union

revision: str = "zr_merge_quality_and_optim"
down_revision: Union[str, Sequence[str], None] = ("zq_add_quality_score", "optim_ai_price")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
