"""add onboarding_completed to users

Revision ID: 9f8e7d6c5b4a
Revises: z1a2b3c4d5e6
Create Date: 2026-06-28

"""
from alembic import op
import sqlalchemy as sa

revision = '9f8e7d6c5b4a'
down_revision = 'z1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('onboarding_completed', sa.Boolean(), nullable=False, server_default='false'),
    )


def downgrade() -> None:
    op.drop_column('users', 'onboarding_completed')
