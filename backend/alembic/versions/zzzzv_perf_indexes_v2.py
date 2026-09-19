"""perf: message_threads user_b_id index + direct_messages content_type index

Revision ID: zzzzv_perf_idx_v2
Revises: zzzzu_dismiss_req_i18n
Create Date: 2026-09-19 20:00:00.000000

"""
from alembic import op

revision = "zzzzv_perf_idx_v2"
down_revision = "zzzzu_dismiss_req_i18n"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_message_threads_user_b",
        "message_threads",
        ["user_b_id"],
    )
    op.create_index(
        "ix_dm_content_type_created",
        "direct_messages",
        ["content_type", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_dm_content_type_created", table_name="direct_messages")
    op.drop_index("ix_message_threads_user_b", table_name="message_threads")
