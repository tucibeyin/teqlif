"""add feed personalization tables

Revision ID: p1q2r3s4t5u6
Revises: o0p1q2r3s4t5
Create Date: 2026-06-23

"""
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from alembic import op

revision = 'p1q2r3s4t5u6'
down_revision = 'o0p1q2r3s4t5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_interests',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('category', sa.String(50), nullable=False),
        sa.Column('score', sa.Float(), nullable=False, server_default='0'),
        sa.Column('raw_signals', JSONB(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.UniqueConstraint('user_id', 'category', name='uq_user_interest'),
    )
    op.create_index('ix_user_interests_user_score', 'user_interests', ['user_id', 'score'])

    op.create_table(
        'listing_impressions',
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, primary_key=True),
        sa.Column('listing_id', sa.Integer(), sa.ForeignKey('listings.id', ondelete='CASCADE'), nullable=False, primary_key=True),
        sa.Column('seen_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
    )
    op.create_index('ix_listing_impressions_user_seen', 'listing_impressions', ['user_id', 'seen_at'])


def downgrade() -> None:
    op.drop_index('ix_listing_impressions_user_seen', table_name='listing_impressions')
    op.drop_table('listing_impressions')
    op.drop_index('ix_user_interests_user_score', table_name='user_interests')
    op.drop_table('user_interests')
