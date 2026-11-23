"""users.user_type — CHECK constraint ekle (V1.1 tier değerleri)

Revision ID: zzzzzzzhi_user_type_constraint
Revises: zzzzzzzh_subscription_v11
Create Date: 2026-11-23
"""

from alembic import op

revision = "zzzzzzzhi_user_type_constraint"
down_revision = "zzzzzzzh_subscription_v11"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_check_constraint(
        "users_user_type_check",
        "users",
        "user_type IN ('standard', 'pro', 'pro_plus', 'premium')",
    )


def downgrade() -> None:
    op.drop_constraint("users_user_type_check", "users", type_="check")
