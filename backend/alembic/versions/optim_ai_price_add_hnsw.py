"""Add last_sold_price and HNSW index

Revision ID: optim_ai_price
Revises: h1i2j3k4l5m6
Create Date: 2026-07-06 08:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'optim_ai_price'
down_revision: Union[str, None] = '0aa83211ce5d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('listings', sa.Column('last_sold_price', sa.Float(), nullable=True))
    op.add_column('listings', sa.Column('last_start_price', sa.Float(), nullable=True))
    op.create_index(op.f('ix_listings_last_sold_price'), 'listings', ['last_sold_price'], unique=False)
    op.execute("CREATE INDEX IF NOT EXISTS ix_listings_embedding_hnsw ON listings USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_listings_embedding_hnsw;")
    op.drop_index(op.f('ix_listings_last_sold_price'), table_name='listings')
    op.drop_column('listings', 'last_start_price')
    op.drop_column('listings', 'last_sold_price')
