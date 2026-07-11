"""merge gift events and dm media heads

Revision ID: zb_merge_gift_and_media
Revises: z10_add_gift_events, za_add_media_direct_messages
Create Date: 2026-07-11

"""
from typing import Sequence, Union
from alembic import op

revision: str = "zb_merge_gift_and_media"
down_revision: Union[str, Sequence[str], None] = (
    "z10_add_gift_events",
    "za_add_media_direct_messages",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
