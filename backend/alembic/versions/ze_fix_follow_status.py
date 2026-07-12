"""Fix follow status

Revision ID: ze_fix_follow_status
Revises: zd_add_follow_requests
Create Date: 2026-07-12
"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "ze_fix_follow_status"
down_revision: Union[str, Sequence[str], None] = "zd_add_follow_requests"
branch_labels = None
depends_on = None

def upgrade() -> None:
    # Eski kayıtlar 'accepted' (tırnaklı) olarak kaydolmuş olabilir, onları temizleyelim.
    # Ayrıca NULL kalmışsa (bir ihtimal) onları da 'accepted' yapalım.
    op.execute("UPDATE follows SET status = 'accepted' WHERE status = '''accepted''' OR status LIKE '%accepted%';")
    op.execute("UPDATE follows SET status = 'accepted' WHERE status IS NULL;")
    op.execute("ALTER TABLE follows ALTER COLUMN status SET DEFAULT 'accepted';")

def downgrade() -> None:
    pass
