"""analytics_events(event_type, created_at) composite index

Revision ID: zzzzzd_analytics_type_created
Revises: zzzzzc_agent_streams_grant
Create Date: 2026-10-08

PG buffer mimarisinde eklenen sorgular event_type + created_at üzerinde
tarıyor: sync_pg_to_clickhouse_task, sync_swipelive_interests_task,
compute_user_interests_task. (user_id, created_at) zaten vardı; bu
indeks event_type bazlı toplu taramaları hızlandırır.
"""
from typing import Sequence, Union
from alembic import op

revision: str = 'zzzzzd_analytics_type_created'
down_revision: Union[str, Sequence[str], None] = 'zzzzzc_agent_streams_grant'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        'ix_analytics_events_type_created',
        'analytics_events',
        ['event_type', 'created_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_analytics_events_type_created', table_name='analytics_events')
