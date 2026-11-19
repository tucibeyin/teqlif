"""add teqlik_locked_balance to users

Revision ID: zzzzzzzg_locked_balance
Revises: zzzzzzzf_reserved_usernames
Create Date: 2026-11-19

Kazanılan ama tam doğrulanmamış kullanıcılara ait teqlikler
teqlik_locked_balance'da bekler; is_verified olunca teqlik_balance'a geçer.
"""

from alembic import op
import sqlalchemy as sa

revision = "zzzzzzzg_locked_balance"
down_revision = "zzzzzzzf_reserved_usernames"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "teqlik_locked_balance",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "teqlik_locked_balance")
