"""merge pgtrgm head with social links

Revision ID: z8_merge_pgtrgm_social
Revises: 20260706_pgtrgm, z7_add_social_links
Create Date: 2026-07-09

"""
from typing import Union, Sequence
from alembic import op
import sqlalchemy as sa

revision: str = 'z8_merge_pgtrgm_social'
down_revision: Union[str, Sequence[str], None] = ('20260706_pgtrgm', 'z7_add_social_links')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
