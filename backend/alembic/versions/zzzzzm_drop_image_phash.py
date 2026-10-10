"""listings: image_phash kolonu kaldırıldı

pHash tabanlı kopya tespit sistemi kaldırıldı — dead code, hiçbir
yerde enqueue edilmiyordu, sadece CPU harcıyordu.

Revision ID: zzzzzm_drop_image_phash
Revises: zzzzzl_token_version
"""
revision = "zzzzzm_drop_image_phash"
down_revision = "zzzzzl_token_version"
branch_labels = None
depends_on = None

from alembic import op


def upgrade() -> None:
    op.execute("ALTER TABLE listings DROP COLUMN IF EXISTS image_phash")


def downgrade() -> None:
    op.execute(
        "ALTER TABLE listings "
        "ADD COLUMN IF NOT EXISTS image_phash VARCHAR(16)"
    )
