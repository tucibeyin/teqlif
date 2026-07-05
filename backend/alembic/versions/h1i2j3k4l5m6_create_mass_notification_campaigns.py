"""create mass_notification_campaigns

Revision ID: h1i2j3k4l5m6
Revises: 9a8b7c6d5e4f
Create Date: 2026-07-05 18:04:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'h1i2j3k4l5m6'
down_revision = '9a8b7c6d5e4f'
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table(
        'mass_notification_campaigns',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('listing_id', sa.Integer(), nullable=True),
        sa.Column('stream_id', sa.Integer(), nullable=True),
        sa.Column('target_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('sent_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('click_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('spent_tuci', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('spent_free_credits', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['listing_id'], ['listings.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['stream_id'], ['live_streams.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_mass_notification_campaigns_id'), 'mass_notification_campaigns', ['id'], unique=False)
    op.create_index(op.f('ix_mass_notification_campaigns_listing_id'), 'mass_notification_campaigns', ['listing_id'], unique=False)
    op.create_index(op.f('ix_mass_notification_campaigns_stream_id'), 'mass_notification_campaigns', ['stream_id'], unique=False)
    op.create_index('ix_mass_notif_user_created', 'mass_notification_campaigns', ['user_id', 'created_at'], unique=False)

def downgrade() -> None:
    op.drop_index('ix_mass_notif_user_created', table_name='mass_notification_campaigns')
    op.drop_index(op.f('ix_mass_notification_campaigns_stream_id'), table_name='mass_notification_campaigns')
    op.drop_index(op.f('ix_mass_notification_campaigns_listing_id'), table_name='mass_notification_campaigns')
    op.drop_index(op.f('ix_mass_notification_campaigns_id'), table_name='mass_notification_campaigns')
    op.drop_table('mass_notification_campaigns')
