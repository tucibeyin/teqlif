"""add compound indexes and status check constraint to calls

Revision ID: zk_call_compound_indexes
Revises: zj_add_call_duration_seconds
Create Date: 2026-07-16

Changes:
- Add compound index (caller_id, status) — busy-check queries on caller side
- Add compound index (callee_id, status) — busy-check queries on callee side
- Add CHECK constraint on status — prevent invalid values at DB level
"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "zk_call_compound_indexes"
down_revision: Union[str, Sequence[str], None] = "zj_add_call_duration_seconds"
branch_labels = None
depends_on = None

_VALID_STATUSES = ("calling", "active", "ended", "rejected", "missed")
_STATUS_CHECK = "ck_calls_status"
_IDX_CALLER_STATUS = "ix_calls_caller_id_status"
_IDX_CALLEE_STATUS = "ix_calls_callee_id_status"


def upgrade() -> None:
    # Compound indexes: busy-check sorguları için
    # WHERE caller_id=X AND status IN ('calling','active')  →  (caller_id, status) index
    op.create_index(_IDX_CALLER_STATUS, "calls", ["caller_id", "status"])
    op.create_index(_IDX_CALLEE_STATUS, "calls", ["callee_id", "status"])

    # CHECK constraint: geçersiz status değerlerini DB katmanında engelle
    op.create_check_constraint(
        _STATUS_CHECK,
        "calls",
        sa.text(f"status IN {_VALID_STATUSES}"),
    )


def downgrade() -> None:
    op.drop_constraint(_STATUS_CHECK, "calls", type_="check")
    op.drop_index(_IDX_CALLEE_STATUS, table_name="calls")
    op.drop_index(_IDX_CALLER_STATUS, table_name="calls")
