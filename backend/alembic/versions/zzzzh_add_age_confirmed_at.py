"""add age_confirmed_at to users

Revision ID: zzzzh_age_confirmed
Revises: zzzzg_ds_sched_end
Create Date: 2026-08-10
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzh_age_confirmed'
down_revision = 'zzzzg_ds_sched_end'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('age_confirmed_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'age_confirmed_at')
