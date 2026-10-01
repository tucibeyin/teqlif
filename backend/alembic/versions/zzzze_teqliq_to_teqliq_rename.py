"""teqliq → teqliq yeniden adlandırma

Revision ID: zzzze_teqliq_to_teqliq_rename
Revises: zzzzd_d2_d4_d5_model_fixes
Create Date: 2026-09-25
"""
from alembic import op

revision = "zzzze_teqliq_to_teqliq_rename"
down_revision = "zzzzd_d2_d4_d5_model_fixes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE teqliq_transactions RENAME TO teqliq_transactions")
    op.execute("ALTER INDEX ix_teqliq_transactions_user_created RENAME TO ix_teqliq_transactions_user_created")
    op.execute("ALTER TABLE users RENAME COLUMN teqliq_balance TO teqliq_balance")


def downgrade() -> None:
    op.execute("ALTER TABLE users RENAME COLUMN teqliq_balance TO teqliq_balance")
    op.execute("ALTER INDEX ix_teqliq_transactions_user_created RENAME TO ix_teqliq_transactions_user_created")
    op.execute("ALTER TABLE teqliq_transactions RENAME TO teqliq_transactions")
