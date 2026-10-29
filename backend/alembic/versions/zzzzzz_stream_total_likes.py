"""live_streams.total_likes kolonu

Revision ID: zzzzzz_stream_total_likes
Revises: zzzzzy_streams_host_idx
Create Date: 2026-10-29
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzzz_stream_total_likes'
down_revision = 'zzzzzy_streams_host_idx'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'live_streams',
        sa.Column('total_likes', sa.Integer(), nullable=False, server_default='0'),
    )


def downgrade() -> None:
    op.drop_column('live_streams', 'total_likes')
