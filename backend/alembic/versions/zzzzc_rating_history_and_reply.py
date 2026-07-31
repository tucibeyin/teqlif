"""add rating_history table and reply columns to ratings

Revision ID: zzzzc_rating_history_and_reply
Revises: zzzzb_add_locale_updated_at
Create Date: 2026-07-31
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "zzzzc_rating_history_and_reply"
down_revision: Union[str, Sequence[str], None] = "zzzzb_add_locale_updated_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "rating_history",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "rating_id",
            sa.Integer(),
            sa.ForeignKey("ratings.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("comment", sa.String(500), nullable=True),
        sa.Column(
            "changed_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    op.add_column("ratings", sa.Column("reply", sa.String(500), nullable=True))
    op.add_column(
        "ratings",
        sa.Column("replied_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ratings", "replied_at")
    op.drop_column("ratings", "reply")
    op.drop_table("rating_history")
