"""merge: streams_subcategory and loc_keys heads

Revision ID: aab_merge_streams_and_loc
Revises: aaa_error_loc_keys, aaa_live_streams_subcategory
Create Date: 2026-07-26
"""
from alembic import op

revision = 'aab_merge_streams_and_loc'
down_revision = ('aaa_error_loc_keys', 'aaa_live_streams_subcategory')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
