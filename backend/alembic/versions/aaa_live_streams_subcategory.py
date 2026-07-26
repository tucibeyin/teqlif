"""live_streams: add subcategory column

Revision ID: aaa_live_streams_subcategory
Revises: zz_hasar_vasita_all
Create Date: 2026-07-26
"""
from alembic import op
import sqlalchemy as sa

revision = 'aaa_live_streams_subcategory'
down_revision = 'zz_hasar_vasita_all'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'live_streams',
        sa.Column('subcategory', sa.String(100), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('live_streams', 'subcategory')
