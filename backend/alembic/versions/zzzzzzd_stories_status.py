"""stories.status — SRE-122: ARQ async video işleme durumu

Revision ID: zzzzzzd_stories_status
Revises: zzzzzzc_users_last_activ
Create Date: 2026-11-01
"""
import sqlalchemy as sa
from alembic import op

revision = "zzzzzzd_stories_status"
down_revision = "zzzzzzc_users_last_activ"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "stories",
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="ready",
        ),
    )


def downgrade() -> None:
    op.drop_column("stories", "status")
