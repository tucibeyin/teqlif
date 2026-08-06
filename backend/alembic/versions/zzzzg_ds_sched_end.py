"""Add scheduled_end_at to direct_sales

Revision ID: zzzzg_ds_sched_end
Revises: zzzzf_add_direct_sales
Create Date: 2026-08-06
"""
from alembic import op

revision = 'zzzzg_ds_sched_end'
down_revision = 'zzzzf_add_direct_sales'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE direct_sales ADD COLUMN scheduled_end_at TIMESTAMP WITH TIME ZONE"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE direct_sales DROP COLUMN IF EXISTS scheduled_end_at"
    )
