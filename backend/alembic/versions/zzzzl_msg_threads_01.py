"""message_threads tablosu

Revision ID: zzzzl_msg_threads_01
Revises: zzzzk_unique_district_city
Create Date: 2026-09-02
"""
from alembic import op

revision = 'zzzzl_msg_threads_01'
down_revision = 'zzzzk_unique_district_city'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE message_threads (
            user_a_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            user_b_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            is_request BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            PRIMARY KEY (user_a_id, user_b_id),
            CONSTRAINT ordered_user_pair CHECK (user_a_id < user_b_id)
        )
    """)
    op.execute("""
        CREATE INDEX ix_message_threads_user_b ON message_threads(user_b_id)
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS message_threads")
