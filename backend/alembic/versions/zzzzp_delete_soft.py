"""soft delete: conversation + per-message flags

Revision ID: zzzzp_delete_soft
Revises: zzzzon_msg_threads_call
Create Date: 2026-09-05
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzp_delete_soft'
down_revision = 'zzzzon_msg_threads_call'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('message_threads', sa.Column('deleted_at_a', sa.DateTime(timezone=True), nullable=True))
    op.add_column('message_threads', sa.Column('deleted_at_b', sa.DateTime(timezone=True), nullable=True))
    op.add_column('direct_messages', sa.Column('deleted_for_sender', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('direct_messages', sa.Column('deleted_for_receiver', sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column('message_threads', 'deleted_at_a')
    op.drop_column('message_threads', 'deleted_at_b')
    op.drop_column('direct_messages', 'deleted_for_sender')
    op.drop_column('direct_messages', 'deleted_for_receiver')
