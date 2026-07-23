"""hasar field: dropdown → multiselect with new options

Revision ID: zx_hasar_multiselect
Revises: zw_category_fields_schema
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "zx_hasar_multiselect"
down_revision: Union[str, Sequence[str], None] = "zw_category_fields_schema"
branch_labels = None
depends_on = None

_NEW_OPTIONS = [
    # (value, label, parent_option_value, position)
    # parent_option_value='__excl__' marks this as an exclusive option in multiselect
    ("boyali",            "Boyalı",             None,       0),
    ("kazali",            "Kazalı",             None,       1),
    ("hasar_kayitli",     "Hasar Kayıtlı",      None,       2),
    ("agir_hasar_kayitli","Ağır Hasar Kayıtlı", None,       3),
    ("hatasiz",           "Hatasız",            "__excl__", 4),
]


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Update field type to multiselect
    conn.execute(
        sa.text(
            "UPDATE category_fields SET type = 'multiselect' "
            "WHERE key = 'hasar' AND is_active = true"
        )
    )

    # 2. Soft-delete old hasar options
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = false "
            "WHERE field_id IN ("
            "  SELECT id FROM category_fields WHERE key = 'hasar'"
            ")"
        )
    )

    # 3. Insert new options for each hasar field
    rows = conn.execute(
        sa.text("SELECT id FROM category_fields WHERE key = 'hasar' AND is_active = true")
    ).fetchall()

    for (field_id,) in rows:
        for (value, label, pov, pos) in _NEW_OPTIONS:
            conn.execute(
                sa.text(
                    "INSERT INTO field_options (field_id, value, label, parent_option_value, position) "
                    "VALUES (:fid, :v, :l, :pov, :pos)"
                ),
                {"fid": field_id, "v": value, "l": label, "pov": pov, "pos": pos},
            )


def downgrade() -> None:
    conn = op.get_bind()

    # Re-activate old options, deactivate new ones
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = false "
            "WHERE field_id IN (SELECT id FROM category_fields WHERE key = 'hasar') "
            "AND value IN ('boyali','kazali','hasar_kayitli','agir_hasar_kayitli','hatasiz')"
        )
    )
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = true "
            "WHERE field_id IN (SELECT id FROM category_fields WHERE key = 'hasar') "
            "AND value IN ('hasarsiz','boyali','degisen','hasarli')"
        )
    )
    conn.execute(
        sa.text(
            "UPDATE category_fields SET type = 'dropdown' WHERE key = 'hasar'"
        )
    )
