"""hasar field: mark hasar_kayitli and agir_hasar_kayitli as mutually exclusive group

Revision ID: zy_hasar_group_exclusive
Revises: zx_hasar_multiselect
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "zy_hasar_group_exclusive"
down_revision: Union[str, Sequence[str], None] = "zx_hasar_multiselect"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE field_options "
            "SET parent_option_value = 'grp:hasar_seviyesi' "
            "WHERE field_id IN (SELECT id FROM category_fields WHERE key = 'hasar') "
            "AND value IN ('hasar_kayitli', 'agir_hasar_kayitli') "
            "AND is_active = true"
        )
    )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE field_options "
            "SET parent_option_value = NULL "
            "WHERE field_id IN (SELECT id FROM category_fields WHERE key = 'hasar') "
            "AND value IN ('hasar_kayitli', 'agir_hasar_kayitli')"
        )
    )
