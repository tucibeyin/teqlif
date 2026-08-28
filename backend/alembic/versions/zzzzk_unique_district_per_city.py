"""unique district per city

Revision ID: zzzzk_unique_district_city
Revises: zzzzj_consent_ip_locale
Create Date: 2026-08-28

Districts tablosunda (city_id, name) üzerinde UNIQUE kısıtlaması eksikti.
Bu açık nedeniyle aynı ilçe birden fazla kez insert edilebildi ve
DropdownButtonFormField assertion hatasına yol açtı.

Bu migration:
  1. Mevcut duplikat satırları kaldırır (en düşük id'yi saklar).
  2. (city_id, name) çiftine UNIQUE constraint ekler.
"""
from alembic import op
from app.utils.migration_utils import bump_schema_version

revision = 'zzzzk_unique_district_city'
down_revision = 'zzzzj_consent_ip_locale'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        DELETE FROM districts
        WHERE id NOT IN (
            SELECT MIN(id)
            FROM districts
            GROUP BY city_id, name
        )
    """)
    op.execute("""
        ALTER TABLE districts
        ADD CONSTRAINT uq_districts_city_id_name UNIQUE (city_id, name)
    """)
    bump_schema_version()


def downgrade() -> None:
    op.execute("""
        ALTER TABLE districts
        DROP CONSTRAINT IF EXISTS uq_districts_city_id_name
    """)
    bump_schema_version()
