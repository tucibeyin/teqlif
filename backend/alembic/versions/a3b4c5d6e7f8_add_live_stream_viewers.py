"""add live_stream_viewers table

Revision ID: a3b4c5d6e7f8
Revises: z2a3b4c5d6e7
Create Date: 2026-07-02 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'a3b4c5d6e7f8'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'live_stream_viewers',
        sa.Column('stream_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['stream_id'], ['live_streams.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('stream_id', 'user_id'),
    )
    op.create_index('ix_live_stream_viewers_user_id', 'live_stream_viewers', ['user_id'])
    op.create_index('ix_live_stream_viewers_stream_id', 'live_stream_viewers', ['stream_id'])


def downgrade():
    op.drop_index('ix_live_stream_viewers_user_id', table_name='live_stream_viewers')
    op.drop_index('ix_live_stream_viewers_stream_id', table_name='live_stream_viewers')
    op.drop_table('live_stream_viewers')
