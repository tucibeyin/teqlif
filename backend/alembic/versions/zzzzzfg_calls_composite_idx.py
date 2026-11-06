"""calls tablosu bileşik indeksler — SRE-152: get_call_history UNION ALL

Revision ID: zzzzzfg_calls_composite_idx
Revises: zzzzzff_reports_unique
Create Date: 2026-11-06
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzfg_calls_composite_idx"
down_revision = "zzzzzff_reports_unique"
branch_labels = None
depends_on = None


def upgrade():
    op.create_index("ix_calls_caller_started", "calls", ["caller_id", "started_at"])
    op.create_index("ix_calls_callee_started", "calls", ["callee_id", "started_at"])


def downgrade():
    op.drop_index("ix_calls_caller_started", table_name="calls")
    op.drop_index("ix_calls_callee_started", table_name="calls")
