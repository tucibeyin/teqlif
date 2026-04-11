"""add composite index on bids (stream_id, created_at)

Revision ID: n9o0p1q2r3s4
Revises: m8n9o0p1q2r3
Create Date: 2026-04-11

"""
from alembic import op

revision = 'n9o0p1q2r3s4'
down_revision = 'm8n9o0p1q2r3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_bids_stream_created",
        "bids",
        ["stream_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_bids_stream_created", table_name="bids")
