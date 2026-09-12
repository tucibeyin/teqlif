"""performance indexes — favorites, listing_impressions, user_interests, direct_sale_orders

Revision ID: zzzzs_perf_indexes
Revises: zzzzr_stream_status_enum
Create Date: 2026-09-12
"""
from alembic import op

revision = 'zzzzs_perf_indexes'
down_revision = 'zzzzr_stream_status_enum'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # favorites(listing_id) — ilan silindiğinde CASCADE temizliği ve JOIN sorguları
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_favorites_listing_id "
        "ON favorites (listing_id)"
    )
    # listing_impressions(listing_id)
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listing_impressions_listing_id "
        "ON listing_impressions (listing_id)"
    )
    # listing_impressions(seen_at DESC) — zaman bazlı sorgular
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listing_impressions_seen_at "
        "ON listing_impressions (seen_at DESC)"
    )
    # user_interests(category, score DESC) — feed scoring sub-select
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_user_interests_category_score "
        "ON user_interests (category, score DESC)"
    )
    # direct_sale_orders(listing_id)
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_direct_sale_orders_listing_id "
        "ON direct_sale_orders (listing_id)"
    )
    # listings: partial index — sadece aktif ilanlar (en yaygın filtre)
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listings_active_created "
        "ON listings (created_at DESC) WHERE status = 'active'"
    )
    # listings: video feed partial index
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_listings_active_video "
        "ON listings (id) WHERE status = 'active' AND video_url IS NOT NULL"
    )
    # bump schema_version → statik cache otomatik yenilenir
    from app.utils.migration_utils import bump_schema_version
    bump_schema_version()


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_favorites_listing_id")
    op.execute("DROP INDEX IF EXISTS ix_listing_impressions_listing_id")
    op.execute("DROP INDEX IF EXISTS ix_listing_impressions_seen_at")
    op.execute("DROP INDEX IF EXISTS ix_user_interests_category_score")
    op.execute("DROP INDEX IF EXISTS ix_direct_sale_orders_listing_id")
    op.execute("DROP INDEX IF EXISTS ix_listings_active_created")
    op.execute("DROP INDEX IF EXISTS ix_listings_active_video")
