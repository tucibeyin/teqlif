"""add sohbet stream category

Revision ID: u6v7w8x9y0z1
Revises: t5u6v7w8x9y0
Create Date: 2026-06-24

"""
from alembic import op
import sqlalchemy as sa

revision = 'u6v7w8x9y0z1'
down_revision = 't5u6v7w8x9y0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        INSERT INTO categories (key, label, sort_order, is_active)
        VALUES ('sohbet', '🗣 Canlı Sohbet', 0, true)
        ON CONFLICT (key) DO NOTHING
    """)


def downgrade() -> None:
    op.execute("DELETE FROM categories WHERE key = 'sohbet'")
