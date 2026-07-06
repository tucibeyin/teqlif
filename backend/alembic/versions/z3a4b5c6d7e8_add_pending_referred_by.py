"""add pending_referred_by to users

Revision ID: z3a4b5c6d7e8
Revises: z2a3b4c5d6e7
Create Date: 2026-07-06 20:42:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'z3a4b5c6d7e8'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None

def upgrade():
    # add pending_referred_by column to users table
    op.add_column('users', sa.Column('pending_referred_by', sa.String(length=12), nullable=True))

def downgrade():
    # drop pending_referred_by column from users table
    op.drop_column('users', 'pending_referred_by')
