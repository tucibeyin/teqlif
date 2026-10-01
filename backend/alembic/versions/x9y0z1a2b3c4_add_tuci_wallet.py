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
    conn = op.get_bind()

    # tuci_balance kolonu yoksa ekle
    has_col = conn.execute(sa.text(
        "SELECT 1 FROM information_schema.columns "
        "WHERE table_name='users' AND column_name='tuci_balance'"
    )).fetchone()
    if not has_col:
        op.add_column(
            "users",
            sa.Column("tuci_balance", sa.Integer(), nullable=False, server_default="100"),
        )

    # tuci_transactions tablosu yoksa oluştur
    conn.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS tuci_transactions (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id),
            amount INTEGER NOT NULL,
            transaction_type VARCHAR(50) NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
    """))
    conn.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_tuci_transactions_user_id "
        "ON tuci_transactions (user_id)"
    ))


def downgrade() -> None:
    op.drop_index("ix_tuci_transactions_user_id", table_name="tuci_transactions")
    op.drop_table("tuci_transactions")
    op.drop_column("users", "tuci_balance")
