"""teqlik_transactions.try_amount — abonelik TRY fiyatı

Revision ID: zzzzzfi_txns_try_amount
Revises: zzzzzfh_ui_subcat_notnull
Create Date: 2026-11-07
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzfi_txns_try_amount"
down_revision = "zzzzzfh_ui_subcat_notnull"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "teqlik_transactions",
        sa.Column("try_amount", sa.Numeric(10, 2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("teqlik_transactions", "try_amount")
