"""listing FK ondelete SET NULL — reports/purchases/auctions + merge heads

Revision ID: d7e8f9a0b1c2
Revises: c6d7e8f9a0b1, e5f6a7b8c9d0, v7w8x9y0z1a2
Create Date: 2026-07-04 12:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = 'd7e8f9a0b1c2'
down_revision = ('c6d7e8f9a0b1', 'e5f6a7b8c9d0', 'v7w8x9y0z1a2')
branch_labels = None
depends_on = None


def upgrade():
    # ── reports.listing_id: NOT NULL → nullable, FK → SET NULL ───────────────
    op.execute("ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_listing_id_fkey")
    op.alter_column('reports', 'listing_id', nullable=True, existing_type=sa.Integer())
    op.create_foreign_key(
        'fk_reports_listing_id_listings',
        'reports', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )

    # ── purchases.listing_id: zaten nullable, FK → SET NULL ──────────────────
    op.execute("ALTER TABLE purchases DROP CONSTRAINT IF EXISTS purchases_listing_id_fkey")
    op.create_foreign_key(
        'fk_purchases_listing_id_listings',
        'purchases', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )

    # ── auctions.listing_id: zaten nullable, FK → SET NULL ───────────────────
    op.execute("ALTER TABLE auctions DROP CONSTRAINT IF EXISTS auctions_listing_id_fkey")
    op.create_foreign_key(
        'fk_auctions_listing_id_listings',
        'auctions', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )


def downgrade():
    op.drop_constraint('fk_auctions_listing_id_listings', 'auctions', type_='foreignkey')
    op.create_foreign_key(None, 'auctions', 'listings', ['listing_id'], ['id'])

    op.drop_constraint('fk_purchases_listing_id_listings', 'purchases', type_='foreignkey')
    op.create_foreign_key(None, 'purchases', 'listings', ['listing_id'], ['id'])

    op.drop_constraint('fk_reports_listing_id_listings', 'reports', type_='foreignkey')
    op.alter_column('reports', 'listing_id', nullable=False, existing_type=sa.Integer())
    op.create_foreign_key(None, 'reports', 'listings', ['listing_id'], ['id'])
