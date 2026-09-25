"""tuci → teqlik yeniden adlandırma

Revision ID: zzzze_tuci_to_teqlik_rename
Revises: zzzzd_d2_d4_d5_model_fixes
Create Date: 2026-09-25
"""
from alembic import op

revision = "zzzze_tuci_to_teqlik_rename"
down_revision = "zzzzd_d2_d4_d5_model_fixes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE tuci_transactions RENAME TO teqlik_transactions")
    op.execute("ALTER INDEX ix_tuci_transactions_user_created RENAME TO ix_teqlik_transactions_user_created")
    op.execute("ALTER TABLE users RENAME COLUMN tuci_balance TO teqlik_balance")


def downgrade() -> None:
    op.execute("ALTER TABLE users RENAME COLUMN teqlik_balance TO tuci_balance")
    op.execute("ALTER INDEX ix_teqlik_transactions_user_created RENAME TO ix_tuci_transactions_user_created")
    op.execute("ALTER TABLE teqlik_transactions RENAME TO tuci_transactions")
