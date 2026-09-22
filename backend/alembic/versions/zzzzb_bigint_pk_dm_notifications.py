"""fix: BigInteger PK — direct_messages + notifications (TASK-yeni-E)

Revision ID: zzzzb_bigint_pk_dm_notifications
Revises: zzzza_user_interests_unique
Create Date: 2026-09-22 15:00:00.000000
"""
from alembic import op

revision = "zzzzb_bigint_pk_dm_notifications"
down_revision = "zzzza_user_interests_unique"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE direct_messages ALTER COLUMN id TYPE BIGINT")
    op.execute("ALTER TABLE notifications ALTER COLUMN id TYPE BIGINT")


def downgrade() -> None:
    op.execute("ALTER TABLE notifications ALTER COLUMN id TYPE INTEGER")
    op.execute("ALTER TABLE direct_messages ALTER COLUMN id TYPE INTEGER")
