"""user_interests: add subcategory column and index

Revision ID: aac_user_interests_subcategory
Revises: aab_merge_streams_and_loc
Create Date: 2026-07-26
"""
from alembic import op
import sqlalchemy as sa

revision = 'aac_user_interests_subcategory'
down_revision = 'aab_merge_streams_and_loc'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'user_interests',
        sa.Column('subcategory', sa.String(100), nullable=True),
    )
    op.create_index(
        'ix_user_interests_category_subcategory',
        'user_interests',
        ['user_id', 'category', 'subcategory'],
    )


def downgrade() -> None:
    op.drop_index('ix_user_interests_category_subcategory', table_name='user_interests')
    op.drop_column('user_interests', 'subcategory')
