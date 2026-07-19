"""Add had_video and max_participants to calls table

Revision ID: zo_add_video_fields_to_calls
Revises: zn_add_missing_indexes
Create Date: 2026-07-19
"""
from alembic import op
import sqlalchemy as sa

revision = "zo_add_video_fields_to_calls"
down_revision = "zn_add_missing_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("calls", sa.Column("had_video", sa.Boolean(), nullable=False, server_default="false"))
    op.add_column("calls", sa.Column("max_participants", sa.Integer(), nullable=False, server_default="2"))


def downgrade() -> None:
    op.drop_column("calls", "max_participants")
    op.drop_column("calls", "had_video")
