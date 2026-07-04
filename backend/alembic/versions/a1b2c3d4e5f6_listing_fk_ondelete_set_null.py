"""listing FK ondelete SET NULL — reports/purchases/auctions

Revision ID: a1b2c3d4e5f6
Revises: z2a3b4c5d6e7
Create Date: 2026-07-04 10:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = 'a1b2c3d4e5f6'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    # ── reports.listing_id: NOT NULL → nullable, FK → SET NULL ───────────────
    # Mevcut FK'yı bul ve düşür
    op.execute("""
        ALTER TABLE reports
        DROP CONSTRAINT IF EXISTS reports_listing_id_fkey
    """)
    # Kolonu nullable yap
    op.alter_column('reports', 'listing_id', nullable=True, existing_type=sa.Integer())
    # Yeni FK ekle: listing silinince SET NULL
    op.create_foreign_key(
        'fk_reports_listing_id_listings',
        'reports', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )

    # ── purchases.listing_id: zaten nullable, FK → SET NULL ──────────────────
    op.execute("""
        ALTER TABLE purchases
        DROP CONSTRAINT IF EXISTS purchases_listing_id_fkey
    """)
    op.create_foreign_key(
        'fk_purchases_listing_id_listings',
        'purchases', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )

    # ── auctions.listing_id: zaten nullable, FK → SET NULL ───────────────────
    op.execute("""
        ALTER TABLE auctions
        DROP CONSTRAINT IF EXISTS auctions_listing_id_fkey
    """)
    op.create_foreign_key(
        'fk_auctions_listing_id_listings',
        'auctions', 'listings',
        ['listing_id'], ['id'],
        ondelete='SET NULL',
    )


def downgrade():
    # auctions
    op.drop_constraint('fk_auctions_listing_id_listings', 'auctions', type_='foreignkey')
    op.create_foreign_key(None, 'auctions', 'listings', ['listing_id'], ['id'])

    # purchases
    op.drop_constraint('fk_purchases_listing_id_listings', 'purchases', type_='foreignkey')
    op.create_foreign_key(None, 'purchases', 'listings', ['listing_id'], ['id'])

    # reports — geri alalım ama NOT NULL constraint restore etmiyoruz (mevcut NULL değerler olabilir)
    op.drop_constraint('fk_reports_listing_id_listings', 'reports', type_='foreignkey')
    op.create_foreign_key(None, 'reports', 'listings', ['listing_id'], ['id'])
