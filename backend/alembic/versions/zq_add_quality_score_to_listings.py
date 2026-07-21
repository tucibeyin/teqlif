"""add quality_score to listings

Revision ID: zq_add_quality_score
Revises: zp_create_call_participants
Create Date: 2026-07-22
"""
from alembic import op
import sqlalchemy as sa

revision = "zq_add_quality_score"
down_revision = "zp_create_call_participants"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "listings",
        sa.Column("quality_score", sa.Float(), nullable=True),
    )
    op.create_index("ix_listings_quality_score", "listings", ["quality_score"])


def downgrade() -> None:
    op.drop_index("ix_listings_quality_score", table_name="listings")
    op.drop_column("listings", "quality_score")
