"""Add proof_image_url to auctions

Revision ID: a3b4c5d6e7f8
Revises: z2a3b4c5d6e7
Create Date: 2026-06-29 15:52:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a3b4c5d6e7f8'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('auctions', sa.Column('proof_image_url', sa.String(length=2000), nullable=True))


def downgrade():
    op.drop_column('auctions', 'proof_image_url')
