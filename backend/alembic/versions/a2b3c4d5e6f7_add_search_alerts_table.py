"""add search_alerts table

Revision ID: a2b3c4d5e6f7
Revises: z1a2b3c4d5e6
Create Date: 2026-06-27 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = "a2b3c4d5e6f7"
down_revision = "z1a2b3c4d5e6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "search_alerts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("category", sa.String(length=50), nullable=True),
        sa.Column("query", sa.String(length=200), nullable=True),
        sa.Column("max_price", sa.Float(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_search_alerts_user_active", "search_alerts", ["user_id", "is_active"])
    op.create_index(op.f("ix_search_alerts_id"), "search_alerts", ["id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_search_alerts_id"), table_name="search_alerts")
    op.drop_index("ix_search_alerts_user_active", table_name="search_alerts")
    op.drop_table("search_alerts")
