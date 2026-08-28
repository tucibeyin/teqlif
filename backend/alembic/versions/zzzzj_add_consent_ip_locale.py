"""add consent ip and locale columns

Revision ID: zzzzj_consent_ip_locale
Revises: zzzzi_cross_border_consent
Create Date: 2026-08-28

"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzj_consent_ip_locale'
down_revision = 'zzzzi_cross_border_consent'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('cross_border_consent_ip', sa.String(45), nullable=True))
    op.add_column('users', sa.Column('cross_border_consent_locale', sa.String(5), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'cross_border_consent_locale')
    op.drop_column('users', 'cross_border_consent_ip')
