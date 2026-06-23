"""add ad_campaigns table

Revision ID: t5u6v7w8x9y0
Revises: s4t5u6v7w8x9
Create Date: 2026-06-23

"""
from alembic import op
import sqlalchemy as sa

revision = 't5u6v7w8x9y0'
down_revision = 's4t5u6v7w8x9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ad_campaigns",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("listing_id", sa.Integer(), nullable=False),
        sa.Column("seller_id", sa.Integer(), nullable=False),
        sa.Column("total_budget", sa.Float(), nullable=False),
        sa.Column("spent_budget", sa.Float(), nullable=False, server_default="0"),
        sa.Column("cpc_bid", sa.Float(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
        sa.Column("start_date", sa.Date(), nullable=True),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["listing_id"], ["listings.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["seller_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ad_campaigns_id", "ad_campaigns", ["id"])
    op.create_index("ix_ad_campaigns_listing_id", "ad_campaigns", ["listing_id"])
    op.create_index("ix_ad_campaigns_status", "ad_campaigns", ["status"])
    op.create_index(
        "ix_ad_campaigns_seller_status", "ad_campaigns", ["seller_id", "status"]
    )


def downgrade() -> None:
    op.drop_index("ix_ad_campaigns_seller_status", table_name="ad_campaigns")
    op.drop_index("ix_ad_campaigns_status", table_name="ad_campaigns")
    op.drop_index("ix_ad_campaigns_listing_id", table_name="ad_campaigns")
    op.drop_index("ix_ad_campaigns_id", table_name="ad_campaigns")
    op.drop_table("ad_campaigns")
