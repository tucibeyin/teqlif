"""Merge zt_districts and VPS-only head 14913da997d1

Revision ID: zu_merge_districts_and_vps
Revises: zt_districts, 14913da997d1
Create Date: 2026-07-23
"""
from typing import Sequence, Union

revision: str = "zu_merge_districts_and_vps"
down_revision: Union[str, Sequence[str], None] = ("zt_districts", "14913da997d1")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
