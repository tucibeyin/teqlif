"""add premium_since to users

Revision ID: 4dff374d57e4
Revises: z2a3b4c5d6e7
Create Date: 2026-07-05 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = '4dff374d57e4'
down_revision = 'a3b4c5d6e7f8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users',
        sa.Column('premium_since', sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('users', 'premium_since')
