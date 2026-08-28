"""add cross_border_consent columns to users

Revision ID: zzzzi_cross_border_consent
Revises: zzzzh_age_confirmed
Create Date: 2026-08-28
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzi_cross_border_consent'
down_revision = 'zzzzh_age_confirmed'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('cross_border_consent_given', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('users', sa.Column('cross_border_consent_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('cross_border_consent_version', sa.String(10), nullable=True))
    op.add_column('users', sa.Column('cross_border_consent_revoked_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'cross_border_consent_revoked_at')
    op.drop_column('users', 'cross_border_consent_version')
    op.drop_column('users', 'cross_border_consent_at')
    op.drop_column('users', 'cross_border_consent_given')
