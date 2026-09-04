"""add apns_sandbox to users

Revision ID: zzzzn_add_apns_sandbox
Revises: zzzzm_intl_location
Create Date: 2026-09-04
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzn_add_apns_sandbox'
down_revision = 'zzzzm_intl_location'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('apns_sandbox', sa.Boolean(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'apns_sandbox')
