"""user_devices tablosu — SRE-133: çoklu cihaz FCM desteği

Revision ID: zzzzzze_user_devices
Revises: zzzzzzd_stories_status
Create Date: 2026-11-01
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzze_user_devices"
down_revision = "zzzzzzd_stories_status"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("fcm_token", sa.String(500), nullable=False),
        sa.Column("platform", sa.String(20), nullable=False, server_default="unknown"),
        sa.Column("apns_sandbox", sa.Boolean(), nullable=True),
        sa.Column(
            "last_active_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("NOW()"),
            nullable=False,
        ),
    )
    op.create_index("ix_user_devices_user_id", "user_devices", ["user_id"])
    op.create_index("ix_user_devices_fcm_token", "user_devices", ["fcm_token"], unique=True)

    # Mevcut users.fcm_token değerlerini backfill et
    op.execute(
        sa.text("""
            INSERT INTO user_devices (user_id, fcm_token, platform, last_active_at)
            SELECT id, fcm_token, 'unknown', NOW()
            FROM users
            WHERE fcm_token IS NOT NULL AND fcm_token != ''
            ON CONFLICT (fcm_token) DO NOTHING
        """)
    )


def downgrade() -> None:
    op.drop_index("ix_user_devices_fcm_token", "user_devices")
    op.drop_index("ix_user_devices_user_id", "user_devices")
    op.drop_table("user_devices")
