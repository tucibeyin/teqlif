"""intl_location: countries tablosu, cities→states, country_code NOT NULL

Revision ID: zzzzm_intl_location
Revises: zzzzl_msg_threads_01
Create Date: 2026-09-03
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzm_intl_location'
down_revision = 'zzzzl_msg_threads_01'
branch_labels = None
depends_on = None


def upgrade():
    # 1. countries tablosu
    op.create_table(
        'countries',
        sa.Column('code', sa.String(2), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False),
    )

    # 2. cities → states
    op.rename_table('cities', 'states')

    # 3. states.country_code ekle (nullable — backfill sonrası NOT NULL yapılacak)
    op.add_column('states', sa.Column('country_code', sa.String(2), nullable=True))

    # 4. districts: city_id → state_id
    op.execute('ALTER TABLE districts RENAME COLUMN city_id TO state_id')
    op.execute('ALTER INDEX ix_districts_city_id RENAME TO ix_districts_state_id')
    op.execute('ALTER TABLE districts RENAME CONSTRAINT uq_districts_city_id_name TO uq_districts_state_id_name')
    op.execute('ALTER TABLE districts RENAME CONSTRAINT districts_city_id_fkey TO districts_state_id_fkey')

    # 5. listings.country_code ekle (nullable)
    op.add_column('listings', sa.Column('country_code', sa.String(2), nullable=True))

    # 6. Turkey seed — NOT NULL backfill için gerekli minimal kayıt
    op.execute("INSERT INTO countries (code, name) VALUES ('TR', 'Türkiye')")

    # 7. states backfill
    op.execute("UPDATE states SET country_code = 'TR'")

    # 8. listings backfill
    op.execute("UPDATE listings SET country_code = 'TR'")

    # 9. NOT NULL
    op.alter_column('states', 'country_code', nullable=False)
    op.alter_column('listings', 'country_code', nullable=False)

    # 10. FK constraintleri
    op.create_foreign_key('fk_states_country_code', 'states', 'countries', ['country_code'], ['code'])
    op.create_foreign_key('fk_listings_country_code', 'listings', 'countries', ['country_code'], ['code'])


def downgrade():
    op.drop_constraint('fk_listings_country_code', 'listings', type_='foreignkey')
    op.drop_constraint('fk_states_country_code', 'states', type_='foreignkey')
    op.drop_column('listings', 'country_code')
    op.drop_column('states', 'country_code')
    op.execute('ALTER TABLE districts RENAME CONSTRAINT districts_state_id_fkey TO districts_city_id_fkey')
    op.execute('ALTER TABLE districts RENAME CONSTRAINT uq_districts_state_id_name TO uq_districts_city_id_name')
    op.execute('ALTER INDEX ix_districts_state_id RENAME TO ix_districts_city_id')
    op.execute('ALTER TABLE districts RENAME COLUMN state_id TO city_id')
    op.rename_table('states', 'cities')
    op.drop_table('countries')
