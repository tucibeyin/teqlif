"""add social links to users

Revision ID: z7_add_social_links
Revises: z6_merge_everything
Create Date: 2026-07-09

"""
from typing import Union, Sequence
import sqlalchemy as sa
from alembic import op

revision: str = 'z7_add_social_links'
down_revision: Union[str, Sequence[str], None] = 'z6_merge_everything'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('instagram_url', sa.String(500), nullable=True))
    op.add_column('users', sa.Column('kick_url', sa.String(500), nullable=True))
    op.add_column('users', sa.Column('twitch_url', sa.String(500), nullable=True))
    op.add_column('users', sa.Column('facebook_url', sa.String(500), nullable=True))
    op.add_column('users', sa.Column('youtube_url', sa.String(500), nullable=True))
    op.add_column('users', sa.Column('tiktok_url', sa.String(500), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'tiktok_url')
    op.drop_column('users', 'youtube_url')
    op.drop_column('users', 'facebook_url')
    op.drop_column('users', 'twitch_url')
    op.drop_column('users', 'kick_url')
    op.drop_column('users', 'instagram_url')
