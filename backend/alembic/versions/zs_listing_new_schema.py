"""Add subcategory, province, district, extra_fields to listings; shrink title to 100

Revision ID: zs_listing_new_schema
Revises: zr_merge_quality_and_optim
Create Date: 2026-07-23
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from typing import Sequence, Union

revision: str = "zs_listing_new_schema"
down_revision: Union[str, Sequence[str], None] = "zr_merge_quality_and_optim"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("listings", sa.Column("subcategory", sa.String(100), nullable=True))
    op.add_column("listings", sa.Column("province", sa.String(100), nullable=True))
    op.add_column("listings", sa.Column("district", sa.String(100), nullable=True))
    op.add_column("listings", sa.Column("extra_fields", JSONB, nullable=True))

    op.create_index("ix_listings_subcategory", "listings", ["subcategory"])
    op.create_index("ix_listings_province", "listings", ["province"])
    op.create_index(
        "ix_listings_extra_fields_gin",
        "listings",
        ["extra_fields"],
        postgresql_using="gin",
    )

    op.alter_column("listings", "title", type_=sa.String(100), existing_nullable=False)


def downgrade() -> None:
    op.alter_column("listings", "title", type_=sa.String(200), existing_nullable=False)

    op.drop_index("ix_listings_extra_fields_gin", table_name="listings")
    op.drop_index("ix_listings_province", table_name="listings")
    op.drop_index("ix_listings_subcategory", table_name="listings")

    op.drop_column("listings", "extra_fields")
    op.drop_column("listings", "district")
    op.drop_column("listings", "province")
    op.drop_column("listings", "subcategory")
