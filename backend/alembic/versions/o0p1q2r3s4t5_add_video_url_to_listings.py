"""add video_url to listings

Revision ID: o0p1q2r3s4t5
Revises: n9o0p1q2r3s4
Create Date: 2026-06-23

"""
import sqlalchemy as sa
from alembic import op

revision = 'o0p1q2r3s4t5'
down_revision = 'n9o0p1q2r3s4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('listings', sa.Column('video_url', sa.String(500), nullable=True))


def downgrade() -> None:
    op.drop_column('listings', 'video_url')
