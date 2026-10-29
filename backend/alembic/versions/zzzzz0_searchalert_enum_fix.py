"""searchalertstatus PG enum: paused + deleted değerleri ekle, passive sil

Revision ID: zzzzz0_searchalert_enum_fix
Revises: zzzzzz_stream_total_likes
Create Date: 2026-10-29
"""
from __future__ import annotations
import sqlalchemy as sa
from alembic import op

revision = 'zzzzz0_searchalert_enum_fix'
down_revision = 'zzzzzz_stream_total_likes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # PostgreSQL enum'a yeni değer eklemek autocommit gerektirir (DDL kısıtı).
    # IF NOT EXISTS: herhangi bir ortamda değer önceden elle eklenmişse idempotent.
    with op.get_context().autocommit_block():
        op.execute(sa.text(
            "ALTER TYPE searchalertstatus ADD VALUE IF NOT EXISTS 'paused'"
        ))
        op.execute(sa.text(
            "ALTER TYPE searchalertstatus ADD VALUE IF NOT EXISTS 'deleted'"
        ))

    # Eski 'passive' kayıtları 'deleted' olarak güncelle (geçiş temizliği).
    op.execute(sa.text(
        "UPDATE search_alerts SET status = 'deleted' WHERE status::text = 'passive'"
    ))


def downgrade() -> None:
    # PostgreSQL enum'dan değer kaldırmak desteklenmiyor; downgrade sadece
    # veri temizliğini geri alır, enum değerleri PG'de kalır (zararsız).
    op.execute(sa.text(
        "UPDATE search_alerts SET status = 'active' WHERE status::text = 'deleted'"
    ))
