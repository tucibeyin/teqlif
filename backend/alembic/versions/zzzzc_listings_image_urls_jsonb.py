"""listings.image_urls TEXT → JSONB + GIN index (D1)

Revision ID: zzzzc_listings_image_urls_jsonb
Revises: zzzza_listings_updated_at_backfi
Create Date: 2026-09-22
"""
from alembic import op

revision = "zzzzc_listings_image_urls_jsonb"
down_revision = "zzzza_listings_updated_at_backfi"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE listings ALTER COLUMN image_urls TYPE JSONB "
        "USING CASE WHEN image_urls IS NULL OR image_urls = '' THEN NULL "
        "ELSE image_urls::JSONB END"
    )
    op.execute(
        "CREATE INDEX ix_listings_image_urls_gin ON listings USING GIN (image_urls)"
    )
    from app.utils.migration_utils import bump_schema_version
    bump_schema_version()


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_image_urls_gin")
    op.execute(
        "ALTER TABLE listings ALTER COLUMN image_urls TYPE TEXT "
        "USING CASE WHEN image_urls IS NULL THEN NULL ELSE image_urls::TEXT END"
    )
    from app.utils.migration_utils import bump_schema_version
    bump_schema_version()
