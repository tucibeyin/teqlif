"""add bio and website_url to users

Revision ID: z1a2b3c4d5e6
Revises: y0z1a2b3c4d5
Create Date: 2026-06-25

"""
from alembic import op
import sqlalchemy as sa

revision = 'z1a2b3c4d5e6'
down_revision = 'y0z1a2b3c4d5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('bio', sa.String(150), nullable=True))
    op.add_column('users', sa.Column('website_url', sa.String(500), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'website_url')
    op.drop_column('users', 'bio')
