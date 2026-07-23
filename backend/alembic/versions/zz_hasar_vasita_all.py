"""Add hasar multiselect field to all relevant vasita subcategories

Revision ID: zz_hasar_vasita_all
Revises: zy_hasar_group_exclusive
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "zz_hasar_vasita_all"
down_revision: Union[str, Sequence[str], None] = "zy_hasar_group_exclusive"
branch_labels = None
depends_on = None

# subcategory → position for the hasar field (last field index + 1)
_TARGETS = {
    "motosiklet":      6,
    "elektrikli_arac": 6,
    "kamyonet_minibus":6,
    "kamyon_tir":      6,
    "traktor":         5,
    "karavan":         4,
}

_OPTIONS = [
    ("boyali",             "Boyalı",             None,                 0),
    ("kazali",             "Kazalı",             None,                 1),
    ("hasar_kayitli",      "Hasar Kayıtlı",      "grp:hasar_seviyesi", 2),
    ("agir_hasar_kayitli", "Ağır Hasar Kayıtlı", "grp:hasar_seviyesi", 3),
    ("hatasiz",            "Hatasız",            "__excl__",           4),
]


def upgrade() -> None:
    conn = op.get_bind()
    for subcategory, position in _TARGETS.items():
        result = conn.execute(
            sa.text(
                "INSERT INTO category_fields "
                "(subcategory, key, label_key, type, required, position, unit, depends_on) "
                "VALUES (:sub, 'hasar', 'extraField_hasar', 'multiselect', false, :pos, NULL, NULL) "
                "RETURNING id"
            ),
            {"sub": subcategory, "pos": position},
        )
        field_id = result.fetchone()[0]
        for (value, label, pov, opt_pos) in _OPTIONS:
            conn.execute(
                sa.text(
                    "INSERT INTO field_options (field_id, value, label, parent_option_value, position) "
                    "VALUES (:fid, :v, :l, :pov, :p)"
                ),
                {"fid": field_id, "v": value, "l": label, "pov": pov, "p": opt_pos},
            )


def downgrade() -> None:
    conn = op.get_bind()
    subcategories = list(_TARGETS.keys())
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = false "
            "WHERE field_id IN ("
            "  SELECT id FROM category_fields "
            "  WHERE key = 'hasar' AND subcategory = ANY(:subs)"
            ")"
        ),
        {"subs": subcategories},
    )
    conn.execute(
        sa.text(
            "UPDATE category_fields SET is_active = false "
            "WHERE key = 'hasar' AND subcategory = ANY(:subs)"
        ),
        {"subs": subcategories},
    )
