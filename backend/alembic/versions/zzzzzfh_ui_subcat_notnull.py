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
    # subcategory IS NULL olan satırlar arasında (user_id, category) duplicate'leri
    # temizle — NULL != NULL olduğundan kısıt daha önce çalışmadı.
    op.execute("""
        DELETE FROM user_interests a
        USING user_interests b
        WHERE a.user_id = b.user_id
          AND a.category = b.category
          AND a.subcategory IS NULL
          AND b.subcategory IS NULL
          AND a.id < b.id
    """)
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
