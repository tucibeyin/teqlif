"""reports unique(reporter_id, listing_id) + reason VARCHAR(1000)

Revision ID: zzzzzff_reports_unique
Revises: zzzzzze_user_devices
Create Date: 2026-11-06
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzff_reports_unique"
down_revision = "zzzzzze_user_devices"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "reports",
        "reason",
        existing_type=sa.String(200),
        type_=sa.String(1000),
        existing_nullable=False,
    )
    op.create_unique_constraint(
        "uq_reports_reporter_listing",
        "reports",
        ["reporter_id", "listing_id"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_reports_reporter_listing", "reports", type_="unique")
    op.alter_column(
        "reports",
        "reason",
        existing_type=sa.String(1000),
        type_=sa.String(200),
        existing_nullable=False,
    )
