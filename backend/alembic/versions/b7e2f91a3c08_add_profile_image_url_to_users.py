"""add_profile_image_url_to_users

Revision ID: b7e2f91a3c08
Revises: a3f8c21d9e47
Create Date: 2026-03-15 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b7e2f91a3c08'
down_revision: Union[str, Sequence[str], None] = 'a3f8c21d9e47'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('profile_image_url', sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'profile_image_url')
