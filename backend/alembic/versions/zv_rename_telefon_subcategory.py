"""Rename subcategory telefon -> cep_telefonu in listings table

Revision ID: zv_rename_telefon_subcategory
Revises: zu_merge_districts_and_vps
Create Date: 2026-07-23
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "zv_rename_telefon_subcategory"
down_revision: Union[str, Sequence[str], None] = "zu_merge_districts_and_vps"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        sa.text(
            "UPDATE listings SET subcategory = 'cep_telefonu' WHERE subcategory = 'telefon'"
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            "UPDATE listings SET subcategory = 'telefon' WHERE subcategory = 'cep_telefonu'"
        )
    )
