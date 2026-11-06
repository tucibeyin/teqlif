"""user_interests.subcategory NOT NULL default empty string

Revision ID: zzzzzfh_ui_subcat_notnull
Revises: zzzzzfg_calls_composite_idx
Create Date: 2026-11-06
"""
from alembic import op
import sqlalchemy as sa

revision = "zzzzzfh_ui_subcat_notnull"
down_revision = "zzzzzfg_calls_composite_idx"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "UPDATE user_interests SET subcategory = '' WHERE subcategory IS NULL"
    )
    op.alter_column(
        "user_interests",
        "subcategory",
        existing_type=sa.String(length=100),
        nullable=False,
        server_default="",
    )


def downgrade():
    op.alter_column(
        "user_interests",
        "subcategory",
        existing_type=sa.String(length=100),
        nullable=True,
        server_default=None,
    )
