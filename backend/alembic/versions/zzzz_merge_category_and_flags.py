"""Merge aae_clean_option_flags and zzz_normalize_category_slugs heads

Revision ID: zzzz_merge_category_and_flags
Revises: aae_clean_option_flags, zzz_normalize_category_slugs
Create Date: 2026-07-28
"""
from typing import Sequence, Union

revision: str = "zzzz_merge_category_and_flags"
down_revision: Union[str, Sequence[str], None] = (
    "aae_clean_option_flags",
    "zzz_normalize_category_slugs",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
