"""add fts search_vector to listings

Revision ID: b2c3d4e5f6a7
Revises: a9b8c7d6e5f4
Create Date: 2026-03-21

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import TSVECTOR


revision = 'b2c3d4e5f6a7'
down_revision = 'a9b8c7d6e5f4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Sütun ekle
    op.add_column('listings', sa.Column('search_vector', TSVECTOR, nullable=True))

    # 2. GIN index oluştur
    op.create_index(
        'ix_listings_search_vector',
        'listings',
        ['search_vector'],
        postgresql_using='gin',
    )

    # 3. Mevcut ilanları doldur
    op.execute("""
        UPDATE listings
        SET search_vector = to_tsvector('turkish', title || ' ' || coalesce(description, ''))
        WHERE is_deleted = FALSE
    """)

    # 4. Trigger: INSERT ve UPDATE'te otomatik güncelleme
    op.execute("""
        CREATE TRIGGER listings_search_vector_update
        BEFORE INSERT OR UPDATE OF title, description ON listings
        FOR EACH ROW EXECUTE FUNCTION
        tsvector_update_trigger(search_vector, 'pg_catalog.turkish', title, description)
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS listings_search_vector_update ON listings")
    op.drop_index('ix_listings_search_vector', table_name='listings')
    op.drop_column('listings', 'search_vector')
