"""tuci kolon adları → teqlik yeniden adlandırma

Revision ID: zzzzza_tuci_column_renames
Revises: zzzzz_listing_offers_status
Create Date: 2026-10-03
"""
from alembic import op

revision = "zzzzza_tuci_column_renames"
down_revision = "zzzzz_listing_offers_status"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE gift_events RENAME COLUMN cost_tuci TO cost_teqlik")
    op.execute("ALTER TABLE mass_notification_campaigns RENAME COLUMN spent_tuci TO spent_teqlik")


def downgrade() -> None:
    op.execute("ALTER TABLE mass_notification_campaigns RENAME COLUMN spent_teqlik TO spent_tuci")
    op.execute("ALTER TABLE gift_events RENAME COLUMN cost_teqlik TO cost_tuci")
