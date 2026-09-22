"""listings.updated_at backfill — NULL → created_at

Revision ID: zzzza_listings_updated_at_backfi
Revises: zzzzb_bigint_pk_dm_notifications
Create Date: 2026-09-22
"""
from alembic import op

revision = "zzzza_listings_updated_at_backfi"
down_revision = "zzzzb_bigint_pk_dm_notifications"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("UPDATE listings SET updated_at = created_at WHERE updated_at IS NULL")


def downgrade() -> None:
    pass
