"""subscription V2: tier rename + kolon yeniden adlandırma

pro/pro_plus/premium → tier1/tier2/tier3
pro_expires_at → sub_expires_at
pro_grace_until → sub_grace_until
CHECK constraint güncellendi

Revision ID: zzzzzzzj_subscription_v2
Revises: zzzzzzzhi_user_type_constraint
Create Date: 2026-11-24
"""

from alembic import op

revision = "zzzzzzzj_subscription_v2"
down_revision = "zzzzzzzhi_user_type_constraint"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Kolon yeniden adlandırma
    op.execute(
        "ALTER TABLE users RENAME COLUMN pro_expires_at TO sub_expires_at"
    )
    op.execute(
        "ALTER TABLE users RENAME COLUMN pro_grace_until TO sub_grace_until"
    )

    # 2. Eski CHECK constraint kaldır
    op.execute(
        "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check"
    )

    # 3. Tier değerlerini güncelle
    op.execute(
        "UPDATE users SET user_type = 'tier3' WHERE user_type = 'premium'"
    )
    op.execute(
        "UPDATE users SET user_type = 'tier2' WHERE user_type = 'pro_plus'"
    )
    op.execute(
        "UPDATE users SET user_type = 'tier1' WHERE user_type = 'pro'"
    )

    # 4. Yeni CHECK constraint ekle
    op.create_check_constraint(
        "users_user_type_check",
        "users",
        "user_type IN ('standard', 'tier1', 'tier2', 'tier3')",
    )

    # 5. Partial index'i yeniden oluştur (eski pro index'ini kaldır)
    op.execute(
        "DROP INDEX IF EXISTS ix_users_user_type_sub_expires"
    )
    op.execute(
        "CREATE INDEX ix_users_user_type_sub_expires "
        "ON users (user_type, sub_expires_at) "
        "WHERE user_type IN ('tier1', 'tier2', 'tier3')"
    )


def downgrade() -> None:
    op.execute(
        "DROP INDEX IF EXISTS ix_users_user_type_sub_expires"
    )
    op.execute(
        "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check"
    )
    op.execute(
        "UPDATE users SET user_type = 'pro' WHERE user_type = 'tier1'"
    )
    op.execute(
        "UPDATE users SET user_type = 'pro_plus' WHERE user_type = 'tier2'"
    )
    op.execute(
        "UPDATE users SET user_type = 'premium' WHERE user_type = 'tier3'"
    )
    op.create_check_constraint(
        "users_user_type_check",
        "users",
        "user_type IN ('standard', 'pro', 'pro_plus', 'premium')",
    )
    op.execute(
        "ALTER TABLE users RENAME COLUMN sub_grace_until TO pro_grace_until"
    )
    op.execute(
        "ALTER TABLE users RENAME COLUMN sub_expires_at TO pro_expires_at"
    )
