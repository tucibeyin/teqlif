"""add notification_prefs to users

Revision ID: c1e3a52f8b19
Revises: b7e2f91a3c08
Create Date: 2026-03-16

"""
from alembic import op
import sqlalchemy as sa


revision = 'c1e3a52f8b19'
down_revision = 'b7e2f91a3c08'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('notification_prefs', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'notification_prefs')
