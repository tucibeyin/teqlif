"""Remove CVT vites option; make renk field required

Revision ID: aaa_vites_cvt_renk_required
Revises: zz_hasar_vasita_all
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aaa_vites_cvt_renk_required"
down_revision: Union[str, Sequence[str], None] = "zz_hasar_vasita_all"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Soft-delete CVT from all vites fields
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = false "
            "WHERE value = 'cvt' "
            "AND field_id IN (SELECT id FROM category_fields WHERE key = 'vites')"
        )
    )

    # 2. Make renk required everywhere
    conn.execute(
        sa.text("UPDATE category_fields SET required = true WHERE key = 'renk'")
    )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE field_options SET is_active = true "
            "WHERE value = 'cvt' "
            "AND field_id IN (SELECT id FROM category_fields WHERE key = 'vites')"
        )
    )
    conn.execute(
        sa.text("UPDATE category_fields SET required = false WHERE key = 'renk'")
    )
