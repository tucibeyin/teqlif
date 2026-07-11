"""Add media columns to direct_messages

Revision ID: za_add_media_direct_messages
Revises: z9_add_txn_reference
Create Date: 2026-07-11

Yeni sütunlar:
  content_type  — 'text' | 'voice' | 'image' | 'video' | 'file'
  media_url     — MinIO nesne URL'si
  thumbnail_url — Görsel/video önizlemesi URL'si
  duration_secs — Ses/video süresi (saniye)
  file_name     — Dosya gönderimlerinde gösterilecek isim
  file_size     — Bayt cinsinden boyut
"""
from typing import Union, Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "za_add_media_direct_messages"
down_revision: Union[str, Sequence[str], None] = "z9_add_txn_reference"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "direct_messages",
        sa.Column("content_type", sa.String(20), nullable=False, server_default="text"),
    )
    op.add_column("direct_messages", sa.Column("media_url", sa.String(500), nullable=True))
    op.add_column("direct_messages", sa.Column("thumbnail_url", sa.String(500), nullable=True))
    op.add_column("direct_messages", sa.Column("duration_secs", sa.SmallInteger(), nullable=True))
    op.add_column("direct_messages", sa.Column("file_name", sa.String(255), nullable=True))
    op.add_column("direct_messages", sa.Column("file_size", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("direct_messages", "file_size")
    op.drop_column("direct_messages", "file_name")
    op.drop_column("direct_messages", "duration_secs")
    op.drop_column("direct_messages", "thumbnail_url")
    op.drop_column("direct_messages", "media_url")
    op.drop_column("direct_messages", "content_type")
