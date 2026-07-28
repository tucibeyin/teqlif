"""add locale_updated_at to users

Revision ID: zzzzb_add_locale_updated_at
Revises: zzzza_norm_subcat_slugs
Create Date: 2026-07-28
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "zzzzb_add_locale_updated_at"
down_revision: Union[str, Sequence[str], None] = "zzzza_norm_subcat_slugs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("locale_updated_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "locale_updated_at")
