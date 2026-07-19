"""Create call_participants table

Revision ID: zp_create_call_participants
Revises: zo_add_video_fields_to_calls
Create Date: 2026-07-19
"""
from alembic import op
import sqlalchemy as sa

revision = "zp_create_call_participants"
down_revision = "zo_add_video_fields_to_calls"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "call_participants",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("call_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),       # initiator | callee | guest
        sa.Column("status", sa.String(length=16), nullable=False),     # invited | ringing | joined | left | rejected | timeout | removed
        sa.Column("invited_by", sa.Integer(), nullable=True),
        sa.Column("livekit_token", sa.Text(), nullable=True),
        sa.Column("invited_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ringing_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("left_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["call_id"], ["calls.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invited_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index("idx_call_participants_call_id", "call_participants", ["call_id"])
    op.create_index("idx_call_participants_user_id", "call_participants", ["user_id"])
    # fast lookup: is this user already a participant in this call?
    op.create_index("idx_call_participants_call_user", "call_participants", ["call_id", "user_id"])


def downgrade() -> None:
    op.drop_index("idx_call_participants_call_user", table_name="call_participants")
    op.drop_index("idx_call_participants_user_id", table_name="call_participants")
    op.drop_index("idx_call_participants_call_id", table_name="call_participants")
    op.drop_table("call_participants")
