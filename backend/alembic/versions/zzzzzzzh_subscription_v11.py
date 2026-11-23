"""subscription V1.1 — users tablosuna yeni alanlar

Revision ID: zzzzzzzh_subscription_v11
Revises: zzzzzzzg_locked_balance
Create Date: 2026-11-23

Eklenenler:
  auto_renew_enabled        — iptal / downgrade pending durumu
  pending_tier              — downgrade hedef tier (DID_CHANGE_RENEWAL_PREF)
  last_tier                 — EXPIRED öncesi tier (win-back için)
  monthly_stream_seconds_used — bu ay kullanılan yayın süresi (saniye)
  monthly_stream_reset_at   — aylık sayaç son sıfırlanma zamanı
"""

from alembic import op
import sqlalchemy as sa

revision = "zzzzzzzh_subscription_v11"
down_revision = "zzzzzzzg_locked_balance"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column(
        "auto_renew_enabled",
        sa.Boolean(),
        nullable=False,
        server_default="true",
    ))
    op.add_column("users", sa.Column(
        "pending_tier",
        sa.String(20),
        nullable=True,
    ))
    op.add_column("users", sa.Column(
        "last_tier",
        sa.String(20),
        nullable=True,
    ))
    op.add_column("users", sa.Column(
        "monthly_stream_seconds_used",
        sa.Integer(),
        nullable=False,
        server_default="0",
    ))
    op.add_column("users", sa.Column(
        "monthly_stream_reset_at",
        sa.DateTime(timezone=True),
        nullable=True,
    ))


def downgrade() -> None:
    op.drop_column("users", "monthly_stream_reset_at")
    op.drop_column("users", "monthly_stream_seconds_used")
    op.drop_column("users", "last_tier")
    op.drop_column("users", "pending_tier")
    op.drop_column("users", "auto_renew_enabled")
