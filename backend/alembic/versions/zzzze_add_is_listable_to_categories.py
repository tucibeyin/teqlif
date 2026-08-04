"""Add is_listable column to categories table

Revision ID: zzzze_add_is_listable_to_categories
Revises: zzzzb_add_locale_updated_at
Create Date: 2026-08-04
"""
from alembic import op
import sqlalchemy as sa
from app.utils.migration_utils import bump_schema_version

revision: str = "zzzze_category_is_listable"
down_revision = "zzzzc_rating_history_and_reply"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Sütunu ekle — varsayılan TRUE (tüm mevcut kategoriler ilan kategorisi)
    op.add_column(
        "categories",
        sa.Column(
            "is_listable",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )

    # 2. Data migration — chat kategorisi ilan yapılamaz
    op.execute("UPDATE categories SET is_listable = FALSE WHERE key = 'chat'")

    # 3. Şema değişti → catalog cache'ini geçersiz kıl
    bump_schema_version()


def downgrade() -> None:
    op.drop_column("categories", "is_listable")
    # Şema değişti → catalog cache'ini geçersiz kıl
    bump_schema_version()
