"""add vector embeddings to listings and users

Revision ID: q2r3s4t5u6v7
Revises: p1q2r3s4t5u6
Create Date: 2026-06-23

Gereksinim: PostgreSQL'de pgvector extension yüklü olmalı.
  sudo apt install postgresql-17-pgvector   (VPS'te bir kez)
  CREATE EXTENSION IF NOT EXISTS vector;    (database.py startup'ında otomatik çalışır)
"""
from alembic import op
import sqlalchemy as sa

# pgvector'ün Alembic için render fonksiyonu
try:
    from pgvector.sqlalchemy import Vector
except ImportError:
    # Migration sırasında pgvector kurulu değilse fallback
    Vector = None

revision = 'q2r3s4t5u6v7'
down_revision = 'p1q2r3s4t5u6'
branch_labels = None
depends_on = None

VECTOR_DIM = 384


def upgrade() -> None:
    # pgvector extension'ını aktifleştir (idempotent)
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    # listings.embedding — ilan metni + kategori embedding'i (sentence-transformer)
    op.add_column(
        'listings',
        sa.Column('embedding', sa.Text(), nullable=True),  # geçici Text
    )
    op.execute("ALTER TABLE listings ALTER COLUMN embedding TYPE vector(384) USING NULL")
    op.execute("ALTER TABLE listings ALTER COLUMN embedding DROP NOT NULL")

    # users.preference_embedding — kullanıcı ilgi vektörü
    op.add_column(
        'users',
        sa.Column('preference_embedding', sa.Text(), nullable=True),
    )
    op.execute("ALTER TABLE users ALTER COLUMN preference_embedding TYPE vector(384) USING NULL")
    op.execute("ALTER TABLE users ALTER COLUMN preference_embedding DROP NOT NULL")

    # IVFFlat index: yaklaşık en-yakın-komşu araması için
    # lists=100 → ~10.000-100.000 ilan için uygun
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_listings_embedding_ivfflat
        ON listings
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_users_preference_embedding_ivfflat
        ON users
        USING ivfflat (preference_embedding vector_cosine_ops)
        WITH (lists = 10)
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_embedding_ivfflat")
    op.execute("DROP INDEX IF EXISTS ix_users_preference_embedding_ivfflat")
    op.drop_column('listings', 'embedding')
    op.drop_column('users', 'preference_embedding')
