"""add reference_id and reference_type to tuci_transactions

Revision ID: z9_add_txn_reference
Revises: z8_merge_pgtrgm_social
Create Date: 2026-07-11

"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "z9_add_txn_reference"
down_revision: Union[str, Sequence[str], None] = "z8_merge_pgtrgm_social"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("tuci_transactions", sa.Column("reference_id", sa.Integer(), nullable=True))
    op.add_column("tuci_transactions", sa.Column("reference_type", sa.String(20), nullable=True))


def downgrade() -> None:
    op.drop_column("tuci_transactions", "reference_type")
    op.drop_column("tuci_transactions", "reference_id")
