"""v18: user_type kolonu — is_premium bool kaldırıldı

Revision ID: zzzzzv_v18_user_type
Revises: zzzzzu_v17_stream_multi_node
Create Date: 2026-10-22
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzzv_v18_user_type'
down_revision = 'zzzzzu_v17_stream_multi_node'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column(
        'user_type', sa.String(20), nullable=False, server_default='standard'
    ))
    op.execute("UPDATE users SET user_type = 'pro' WHERE is_premium = TRUE")
    op.drop_column('users', 'is_premium')


def downgrade():
    op.add_column('users', sa.Column(
        'is_premium', sa.Boolean(), nullable=False, server_default='false'
    ))
    op.execute("UPDATE users SET is_premium = TRUE WHERE user_type = 'pro'")
    op.drop_column('users', 'user_type')
