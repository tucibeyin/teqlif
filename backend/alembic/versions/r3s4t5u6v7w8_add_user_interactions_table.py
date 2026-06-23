"""add user_interactions table

Revision ID: r3s4t5u6v7w8
Revises: q2r3s4t5u6v7
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa

revision = 'r3s4t5u6v7w8'
down_revision = 'q2r3s4t5u6v7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_interactions',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('item_id', sa.Integer(), nullable=False),
        sa.Column('item_type', sa.String(20), nullable=False),
        sa.Column('interaction_type', sa.String(30), nullable=False),
        sa.Column('duration_seconds', sa.Float(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_user_interactions_user_item', 'user_interactions', ['user_id', 'item_id'])
    op.create_index('ix_user_interactions_created', 'user_interactions', ['created_at'])
    op.create_index('ix_user_interactions_id', 'user_interactions', ['id'])


def downgrade() -> None:
    op.drop_index('ix_user_interactions_user_item', table_name='user_interactions')
    op.drop_index('ix_user_interactions_created', table_name='user_interactions')
    op.drop_index('ix_user_interactions_id', table_name='user_interactions')
    op.drop_table('user_interactions')
