"""Change yil field type from number to dropdown (client generates year list)

Revision ID: aab_yil_dropdown
Revises: aaa_vites_cvt_renk_required
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aab_yil_dropdown"
down_revision: Union[str, Sequence[str], None] = "aaa_vites_cvt_renk_required"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.get_bind().execute(
        sa.text("UPDATE category_fields SET type = 'dropdown' WHERE key = 'yil'")
    )


def downgrade() -> None:
    op.get_bind().execute(
        sa.text("UPDATE category_fields SET type = 'number' WHERE key = 'yil'")
    )
