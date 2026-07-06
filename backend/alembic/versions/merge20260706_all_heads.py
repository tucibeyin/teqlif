"""Merge all heads into single branch

Revision ID: merge20260706_all_heads
Revises: b4c5d6e7f8a9, b9c0d1e2f3a4, c4d5e6f7a8b9, e3f4a5b6c7d8, e5f6a7b8c9d0, f2g3h4i5j6k7, f7e8d9c0b1a2, h1i2j3k4l5m6, h3i4j5k6l7m8, l7m8n9o0p1q2, ref20260706_expires, v7w8x9y0z1a2
Create Date: 2026-07-06 17:10:00.000000
"""
from alembic import op
import sqlalchemy as sa
from typing import Sequence, Union

revision: str = 'merge20260706_all_heads'
down_revision: Union[str, Sequence[str]] = (
    'b4c5d6e7f8a9',
    'b9c0d1e2f3a4',
    'c4d5e6f7a8b9',
    'e3f4a5b6c7d8',
    'e5f6a7b8c9d0',
    'f2g3h4i5j6k7',
    'f7e8d9c0b1a2',
    'h1i2j3k4l5m6',
    'h3i4j5k6l7m8',
    'l7m8n9o0p1q2',
    'ref20260706_expires',
    'v7w8x9y0z1a2',
)
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
