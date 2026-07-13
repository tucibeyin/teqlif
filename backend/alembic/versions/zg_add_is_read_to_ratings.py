"""add is_read to ratings

Revision ID: zg_add_is_read_to_ratings
Revises: zf_add_voip_token
Create Date: 2026-07-13 18:55:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'zg_add_is_read_to_ratings'
down_revision = 'zf_add_voip_token'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('ratings', sa.Column('is_read', sa.Boolean(), server_default='false', nullable=False))

def downgrade():
    op.drop_column('ratings', 'is_read')
