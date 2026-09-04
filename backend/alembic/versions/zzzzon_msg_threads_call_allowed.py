"""message_threads: call_allowed kolonu

Revision ID: zzzzon_msg_threads_call
Revises: zzzzn_add_apns_sandbox
Create Date: 2026-09-04
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzon_msg_threads_call'
down_revision = 'zzzzn_add_apns_sandbox'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'message_threads',
        sa.Column('call_allowed', sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column('message_threads', 'call_allowed')
