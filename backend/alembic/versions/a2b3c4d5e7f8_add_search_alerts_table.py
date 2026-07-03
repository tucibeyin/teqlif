"""add search_alerts table

Revision ID: a2b3c4d5e7f8
Revises: c6d7e8f9a0b1
Create Date: 2026-07-03 12:00:00.000000

NOTE: Bu migration idempotent'tir — tablo zaten varsa hiçbir şey yapmaz.
Önceden create_all() ile oluşturulan ortamlarda güvenle çalışır.
"""
from alembic import op

revision = "a2b3c4d5e7f8"
down_revision = "c6d7e8f9a0b1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS search_alerts (
            id          SERIAL PRIMARY KEY,
            user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            category    VARCHAR(50),
            query       VARCHAR(200),
            max_price   FLOAT,
            is_active   BOOLEAN NOT NULL DEFAULT TRUE,
            created_at  TIMESTAMPTZ DEFAULT now()
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_search_alerts_user_active
        ON search_alerts (user_id, is_active)
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_search_alerts_id
        ON search_alerts (id)
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_search_alerts_user_active")
    op.execute("DROP INDEX IF EXISTS ix_search_alerts_id")
    op.execute("DROP TABLE IF EXISTS search_alerts")
