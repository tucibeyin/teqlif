"""live_streams: (host_id, started_at) bileşik index

Revision ID: zzzzzy_streams_host_idx
Revises: zzzzzx_wallet_v10b
Create Date: 2026-10-29
"""
from __future__ import annotations
from alembic import op

revision = 'zzzzzy_streams_host_idx'
down_revision = 'zzzzzx_wallet_v10b'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        'ix_live_streams_host_id_started_at',
        'live_streams',
        ['host_id', 'started_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_live_streams_host_id_started_at', table_name='live_streams')
