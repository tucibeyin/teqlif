"""Clean architecture option flags: add exclusion_group and is_exclusive, clear overloaded parent_option_value

Revision ID: aae_clean_option_flags
Revises: aac_user_interests_subcategory, aaa_slug_unification
Create Date: 2026-07-27
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aae_clean_option_flags"
down_revision: Union[str, Sequence[str], None] = ("aac_user_interests_subcategory", "aaa_slug_unification")
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add new clean domain columns
    op.add_column("field_options", sa.Column("exclusion_group", sa.String(length=80), nullable=True))
    op.add_column("field_options", sa.Column("is_exclusive", sa.Boolean(), server_default=sa.text("false"), nullable=False))
    
    # 2. Create index for fast grouping lookup
    op.create_index("ix_field_options_exclusion_group", "field_options", ["field_id", "exclusion_group", "is_active"])
    
    # 3. Data migration: move 'grp:%' from overloaded parent_option_value to exclusion_group
    conn = op.get_bind()
    conn.execute(sa.text(
        "UPDATE field_options "
        "SET exclusion_group = SUBSTRING(parent_option_value FROM 5), "
        "    parent_option_value = NULL "
        "WHERE parent_option_value LIKE 'grp:%'"
    ))
    
    # 4. Data migration: move '__excl__' from overloaded parent_option_value to is_exclusive = true
    conn.execute(sa.text(
        "UPDATE field_options "
        "SET is_exclusive = true, "
        "    parent_option_value = NULL "
        "WHERE parent_option_value = '__excl__'"
    ))


def downgrade() -> None:
    conn = op.get_bind()
    # 1. Restore '__excl__'
    conn.execute(sa.text(
        "UPDATE field_options "
        "SET parent_option_value = '__excl__' "
        "WHERE is_exclusive = true"
    ))
    
    # 2. Restore 'grp:%'
    conn.execute(sa.text(
        "UPDATE field_options "
        "SET parent_option_value = CONCAT('grp:', exclusion_group) "
        "WHERE exclusion_group IS NOT NULL"
    ))
    
    # 3. Drop index and columns
    op.drop_index("ix_field_options_exclusion_group", table_name="field_options")
    op.drop_column("field_options", "is_exclusive")
    op.drop_column("field_options", "exclusion_group")
