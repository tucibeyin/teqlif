"""add tuci wallet — tuci_balance on users + tuci_transactions table

Revision ID: x9y0z1a2b3c4
Revises: w8x9y0z1a2b3
Create Date: 2026-06-24 00:00:00.000000
"""
import sqlalchemy as sa
from alembic import op

revision = "x9y0z1a2b3c4"
down_revision = "w8x9y0z1a2b3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("tuci_balance", sa.Integer(), nullable=False, server_default="100"),
    )
    op.create_table(
        "tuci_transactions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("transaction_type", sa.String(50), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_tuci_transactions_user_id", "tuci_transactions", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_tuci_transactions_user_id", table_name="tuci_transactions")
    op.drop_table("tuci_transactions")
    op.drop_column("users", "tuci_balance")
