"""add_plan_type_to_users

Revision ID: f2g3h4i5j6k7
Revises: e1f2a3b4c5d6
Create Date: 2026-07-05 10:57:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'f2g3h4i5j6k7'
down_revision = 'e1f2a3b4c5d6'
branch_labels = None
depends_on = None

def upgrade() -> None:
    # Add plan_type column to users table
    op.add_column('users', sa.Column('plan_type', sa.String(length=20), nullable=True))

def downgrade() -> None:
    # Remove plan_type column from users table
    op.drop_column('users', 'plan_type')
