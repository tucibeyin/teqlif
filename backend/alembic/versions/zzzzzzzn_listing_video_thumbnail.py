"""listings: video_thumbnail_url alanı

Video ilanlarında ilk kare thumbnail ayrı alanda tutulur;
swipe live'da ilan fotoğrafı yerine video ilk karesi gösterilir.

Revision ID: zzzzzzzn_listing_video_thumbnail
Revises: zzzzzzzzm_stream_minutes_bonus
Create Date: 2026-11-28
"""

from alembic import op
import sqlalchemy as sa

revision = "zzzzzzzn_listing_video_thumbnail"
down_revision = "zzzzzzzzm_stream_minutes_bonus"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "listings",
        sa.Column("video_thumbnail_url", sa.String(500), nullable=True),
    )


def downgrade():
    op.drop_column("listings", "video_thumbnail_url")
